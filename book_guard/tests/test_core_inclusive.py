# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A paper session counts both ends: stop page - start page + 1."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
import hashlib

import pytest

from book_guard import _sessions
from book_guard._ebook_sessions import EbookRead
from book_guard._pagenum import Choice, Context, choose
from book_guard._photos import PhotoRecord
from book_guard._sessions import NEEDS_CHECK, NEEDS_QUIZ, TOO_FAST, Session

_T0 = datetime(2026, 10, 2, 20, 0, tzinfo=UTC)


def _p(name: str, page: int | None, minutes: float) -> PhotoRecord:
    taken = (_T0 + timedelta(minutes=minutes)).isoformat()
    return PhotoRecord(
        sha=hashlib.sha256(name.encode()).hexdigest(),
        name=name,
        taken_at=taken,
        uploaded_at=taken,
        kind="page",
        page=page,
    )


def test_pages_count_both_ends() -> None:
    assert Session(_p("a", 1, 0), _p("b", 29, 60), None).pages == 29


def test_same_page_is_one_page() -> None:
    session = Session(_p("a", 10, 0), _p("b", 10, 2), None)
    assert session.pages == 1
    assert session.state == NEEDS_QUIZ


def test_same_page_still_needs_fifty_seconds() -> None:
    assert Session(_p("a", 10, 0), _p("b", 10, 0.5), None).state == TOO_FAST


def test_fifty_seconds_per_page_uses_inclusive_pages() -> None:
    # 29 pages need 29 * 50 s = 24 min 10 s (28 pages would need 23 min 20 s).
    assert Session(_p("a", 1, 0), _p("b", 29, 24), None).state == TOO_FAST
    assert Session(_p("a", 1, 0), _p("b", 29, 25), None).state == NEEDS_QUIZ


def test_missing_page_numbers_count_one() -> None:
    assert Session(_p("a", None, 0), _p("b", None, 1), None).pages == 1


def test_in_app_session_pages_are_unchanged() -> None:
    read = EbookRead(
        session="k",
        isbn="9780140449136",
        start_offset=0,
        end_offset=900,
        start_page=10,
        end_page=30,
        started_at=_T0.isoformat(),
        ended_at=(_T0 + timedelta(minutes=40)).isoformat(),
        text_sha="x",
        received_at=_T0.isoformat(),
    )
    assert read.to_session().pages == 20


def test_check_page_is_drawn_from_start_to_stop() -> None:
    seen = set()
    for i in range(300):
        start, end = _p(f"s{i}", 10, 0), _p(f"e{i}", 13, 40)
        page = _sessions.check_page_for(start, end)
        assert page is not None
        seen.add(page)
    assert seen == {10, 11, 12, 13}


def test_check_page_of_adjacent_and_same_page_sessions() -> None:
    adjacent = _sessions.check_page_for(_p("a", 10, 0), _p("b", 11, 5))
    assert adjacent in {10, 11}
    assert _sessions.check_page_for(_p("a", 10, 0), _p("b", 10, 5)) == 10


def _bare(sha: str, page: int) -> PhotoRecord:
    return PhotoRecord(
        sha=sha, name=sha, taken_at="", uploaded_at="", kind="page", page=page
    )


@pytest.mark.parametrize(
    ("start", "end", "expected"),
    [
        ((51, "start"), (103, "stop"), 97),
        ((10, "a"), (10, "b"), 10),
        ((7, "x"), (8, "y"), 7),
        ((1, "p"), (29, "q"), 15),
    ],
)
def test_check_page_values_are_pinned_for_the_app_port(
    start: tuple[int, str], end: tuple[int, str], expected: int
) -> None:
    # The same literals sit in app/test/src/local_session_test.dart.
    got = _sessions.check_page_for(_bare(start[1], start[0]), _bare(end[1], end[0]))
    assert got == expected


def test_one_page_session_waits_for_its_check_photo() -> None:
    sessions = _sessions.build_sessions([_p("a", 10, 0), _p("b", 10, 2)])
    assert [(s.pages, s.check_page, s.state) for s in sessions] == [
        (1, 10, NEEDS_CHECK)
    ]


def test_stop_on_the_start_page_closes_the_session() -> None:
    sessions = _sessions.build_sessions([_p("a", 50, 0), _p("b", 50, 5)])
    assert [(s.start.name, s.end.name, s.pages) for s in sessions] == [("a", "b", 1)]
    # A later page far away (past MAX_SESSION) does not make b a restart.
    far = [_p("a", 50, 0), _p("b", 50, 5), _p("c", 60, 7 * 60)]
    assert [(s.start.name, s.end.name) for s in _sessions.build_sessions(far)] == [
        ("a", "b")
    ]


def test_same_page_photo_with_a_later_page_soon_after_is_a_restart() -> None:
    # Real, 2026-10-23: p. 302 photographed twice, 224 minutes apart, then
    # p. 336: the credited session is b -> c, never a one-page a -> b.
    photos = [_p("a", 302, 0), _p("b", 302, 224), _p("c", 336, 414)]
    sessions = _sessions.build_sessions(photos)
    assert [(s.start.name, s.end.name, s.pages) for s in sessions] == [("b", "c", 35)]


def test_quick_retake_of_the_start_page_replaces_the_start() -> None:
    photos = [_p("a", 50, 0), _p("b", 50, 0.5), _p("c", 60, 20)]
    sessions = _sessions.build_sessions(photos)
    assert [(s.start.name, s.end.name, s.pages) for s in sessions] == [("b", "c", 11)]


@pytest.mark.parametrize(
    ("found", "context", "expected"),
    [
        ([7], Context(after=7), Choice(7)),
        ([3], Context(after=7), Choice(None, "no page after 7 found on the photo")),
        ([8], Context(after=7), Choice(8)),
    ],
)
def test_stop_page_may_equal_the_start_page(
    found: list[int], context: Context, expected: Choice
) -> None:
    assert choose(found, context) == expected
