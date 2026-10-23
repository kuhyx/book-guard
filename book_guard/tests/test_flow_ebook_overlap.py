# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""In-app reading against paper reading: the same hour never counts twice."""

from __future__ import annotations

from datetime import timedelta
from typing import TYPE_CHECKING

import pytest

from book_guard import (
    _ebook_sessions,
    _ledger,
)
from book_guard._photo_context import context_for
from book_guard._photos import load as load_photos
from book_guard._sessions import NEEDS_QUIZ
from book_guard._state import OVERLAP, snapshot
from book_guard.tests._ebook_flow import (
    NOW,
    map_book,
    send_session,
)
from book_guard.tests._ebook_helpers import middle
from book_guard.tests._flow_helpers import rec, seed_photos

if TYPE_CHECKING:
    from book_guard._paths import Paths


@pytest.fixture
def mapped(bg_paths: Paths) -> Paths:
    """A registered book with its ebook indexed, five pages photographed."""
    return map_book(bg_paths)


def test_two_app_sessions_cannot_overlap(mapped: Paths) -> None:
    assert send_session(mapped).ok
    other = send_session(
        mapped,
        session="0123456789abcdef",
        started_at=(NOW - timedelta(minutes=90)).isoformat(),
        ended_at=(NOW - timedelta(minutes=10)).isoformat(),
    )
    assert not other.ok
    assert "overlaps" in other.message


def test_an_app_session_cannot_overlap_paper_reading(mapped: Paths) -> None:
    records = load_photos(mapped.photos)
    seed_photos(
        mapped,
        *records.values(),
        rec("a", 60, NOW - timedelta(hours=3)),
        rec("b", 70, NOW - timedelta(minutes=90)),
    )
    response = send_session(mapped)
    assert not response.ok
    assert "paper" in response.message


def test_an_open_paper_start_does_not_block_an_app_session(mapped: Paths) -> None:
    # The reader ends a paper session with a stop photo and at once takes the
    # next start photo: switching to the app then must not wait 6 h. If that
    # start is ever closed across the app session, the paper session is the
    # one that does not count (see below), so nothing is credited twice.
    records = load_photos(mapped.photos)
    seed_photos(mapped, *records.values(), rec("a", 60, NOW - timedelta(hours=3)))
    assert send_session(mapped).ok


def test_app_reading_closes_an_open_paper_start(mapped: Paths) -> None:
    # Start photo of p. 40, then the reader switches to the app (40 -> 52),
    # then photographs p. 52 to go on on paper: that is a new start, not
    # the stop of a 40-52 paper session (which would not count anyway).
    records = load_photos(mapped.photos)
    stale = rec("a", 40, NOW - timedelta(hours=3))
    again = rec("b", 52, NOW - timedelta(minutes=30))
    seed_photos(mapped, *records.values(), stale)
    assert send_session(mapped).ok
    snap = snapshot(mapped)
    assert snap.open_start is None  # the app session closed it
    seed_photos(mapped, *records.values(), stale, again)
    snap = snapshot(mapped)
    assert [v.session.session_id for v in snap.sessions] == [
        "session:ebook-abcdef0123456789"
    ]
    assert snap.open_start == again
    ledger = _ledger.load(mapped.ledger, mapped.key_file)
    app = _ebook_sessions.sessions(mapped)
    records = load_photos(mapped.photos)
    stop = context_for("stop_x.jpg", NOW, records, ledger, app)
    assert stop.after == 52


def test_a_paper_start_during_app_reading_still_overlaps(mapped: Paths) -> None:
    assert send_session(mapped).ok
    records = load_photos(mapped.photos)
    seed_photos(
        mapped,
        *records.values(),
        rec("a", 60, NOW - timedelta(minutes=90)),  # while reading in the app
        rec("b", 70, NOW - timedelta(minutes=10)),
    )
    statuses = [v.status for v in snapshot(mapped).sessions]
    assert OVERLAP in statuses


def test_a_flipped_through_paper_session_does_not_block(mapped: Paths) -> None:
    records = load_photos(mapped.photos)
    seed_photos(
        mapped,
        *records.values(),
        rec("a", 60, NOW - timedelta(minutes=100)),
        rec("b", 90, NOW - timedelta(minutes=99)),  # 30 pages in a minute
    )
    assert send_session(mapped).ok


def test_a_paper_session_overlapping_app_reading_does_not_count(
    mapped: Paths,
) -> None:
    assert send_session(mapped).ok
    records = load_photos(mapped.photos)
    seed_photos(
        mapped,
        *records.values(),
        rec("a", 60, NOW - timedelta(minutes=100)),
        rec("b", 61, NOW - timedelta(minutes=50)),
    )
    statuses = {v.session.session_id: v.status for v in snapshot(mapped).sessions}
    paper = next(sid for sid in statuses if "ebook" not in sid)
    assert statuses[paper] == OVERLAP
    assert statuses["session:ebook-abcdef0123456789"] == NEEDS_QUIZ


def test_sessions_at_other_times_do_not_clash(mapped: Paths) -> None:
    records = load_photos(mapped.photos)
    seed_photos(
        mapped,
        *records.values(),
        rec("a", 30, NOW - timedelta(hours=8)),
        rec("b", 40, NOW - timedelta(hours=7)),
    )
    assert send_session(mapped).ok
    later = send_session(
        mapped,
        session="0123456789abcdef",
        start_offset=middle(52),
        end_offset=middle(60),
        started_at=(NOW - timedelta(minutes=50)).isoformat(),
        ended_at=(NOW - timedelta(minutes=5)).isoformat(),
    )
    assert later.ok, later.message
    assert len(_ebook_sessions.load(mapped)) == 2
