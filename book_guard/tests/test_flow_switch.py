# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A book switch closes the open paper start photo, like an in-app session."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

from book_guard import _books, _ledger
from book_guard._ebook_overlap import paper_conflict
from book_guard._photo_context import context_for
from book_guard._photos import load as load_photos
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import add_book, rec, seed_photos

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._photos import PhotoRecord

OTHER = "9788311187948"


def _switched(paths: Paths) -> datetime:
    """Read A, then switch to B (taps happen at ``now``); return that moment."""
    add_book(paths, isbn=OTHER, author="Piercy")
    add_book(paths)  # A, registered last: the one being read
    return _books.switch(paths, OTHER).registered_at


def _start_of_a(at: datetime) -> list[PhotoRecord]:
    return [rec("a", 100, at - timedelta(hours=2))]


def test_a_start_of_one_book_never_pairs_with_a_photo_of_the_next(
    bg_paths: Paths,
) -> None:
    moment = _switched(bg_paths)
    seed_photos(
        bg_paths, *_start_of_a(moment), rec("b", 300, moment + timedelta(hours=1))
    )
    snap = snapshot(bg_paths)
    assert snap.sessions == []
    assert snap.open_start == rec("b", 300, moment + timedelta(hours=1))


def test_the_new_book_pairs_its_own_start_and_stop(bg_paths: Paths) -> None:
    moment = _switched(bg_paths)
    seed_photos(
        bg_paths,
        *_start_of_a(moment),
        rec("b", 300, moment + timedelta(hours=1)),
        rec("c", 310, moment + timedelta(hours=1, minutes=20)),
    )
    (view,) = snapshot(bg_paths).sessions
    assert (view.session.start.page, view.session.end.page) == (300, 310)
    assert view.book is not None
    assert view.book.isbn == OTHER


def test_an_app_session_is_not_blocked_by_a_pair_across_a_switch(
    bg_paths: Paths,
) -> None:
    moment = _switched(bg_paths)
    seed_photos(
        bg_paths, *_start_of_a(moment), rec("b", 300, moment + timedelta(hours=1))
    )
    span = (moment - timedelta(minutes=30), moment + timedelta(minutes=30))
    assert paper_conflict(bg_paths, span, []) is None


def test_without_a_switch_the_same_photos_do_conflict(bg_paths: Paths) -> None:
    moment = datetime.now(tz=UTC)
    add_book(bg_paths)
    seed_photos(
        bg_paths, *_start_of_a(moment), rec("b", 300, moment + timedelta(hours=1))
    )
    span = (moment - timedelta(minutes=30), moment + timedelta(minutes=30))
    assert paper_conflict(bg_paths, span, []) is not None


def test_the_photo_hints_ignore_a_start_from_before_the_switch(
    bg_paths: Paths,
) -> None:
    moment = _switched(bg_paths)
    seed_photos(
        bg_paths, *_start_of_a(moment), rec("b", 300, moment + timedelta(hours=1))
    )
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    records = load_photos(bg_paths.photos)
    later = moment + timedelta(hours=2)
    assert context_for("start_x.jpg", later, records, ledger).near is None
    stop = context_for("stop_x.jpg", later, records, ledger)
    assert stop.after == 300  # the new book's own start, not A's p. 100
