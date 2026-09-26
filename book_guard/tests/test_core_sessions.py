# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_sessions: pairing photos into sessions, check pages, open starts."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from book_guard import _sessions
from book_guard._photos import PhotoRecord
from book_guard._sessions import NEEDS_CHECK, NEEDS_QUIZ, TOO_FAST, Session

_T0 = datetime(2026, 10, 2, 20, 0, tzinfo=UTC)


def _p(name: str, page: int | None, minutes: float) -> PhotoRecord:
    taken = (_T0 + timedelta(minutes=minutes)).isoformat()
    return PhotoRecord(
        sha=name * 20,
        name=name,
        taken_at=taken,
        uploaded_at=taken,
        kind="page",
        page=page,
        text=f"text of {name}",
    )


def test_session_properties() -> None:
    start, end = _p("a", 10, 0), _p("b", 30, 45.5)
    session = Session(start, end, 20)
    assert session.session_id == f"session:{'a' * 16}-{'b' * 16}"
    assert session.pages == 20
    assert session.seconds == 45.5 * 60
    assert session.minutes == 45
    assert session.state == NEEDS_CHECK
    assert session.evidence == [start, end]
    session.check = _p("c", 20, 50)
    assert session.state == NEEDS_QUIZ
    assert session.evidence == [start, session.check, end]


def test_pages_with_missing_numbers() -> None:
    assert Session(_p("a", None, 0), _p("b", None, 1), None).pages == 0


def test_too_fast() -> None:
    session = Session(_p("a", 10, 0), _p("b", 30, 19), None)
    assert session.state == TOO_FAST
    exactly = Session(_p("a", 10, 0), _p("b", 30, 20), None)
    assert exactly.state == NEEDS_QUIZ


def test_check_page_for() -> None:
    start, end = _p("a", 10, 0), _p("b", 30, 40)
    page = _sessions.check_page_for(start, end)
    assert page is not None
    assert 11 <= page <= 29
    assert page == _sessions.check_page_for(start, end)  # deterministic
    assert _sessions.check_page_for(_p("a", 10, 0), _p("b", 11, 5)) is None
    assert _sessions.check_page_for(_p("a", 10, 0), _p("b", 12, 5)) == 11


def test_simple_pair_then_check_photo() -> None:
    start, end = _p("a", 10, 0), _p("b", 30, 40)
    page = _sessions.check_page_for(start, end)
    check = _p("c", page, 41)
    sessions = _sessions.build_sessions([start, end, check])
    assert len(sessions) == 1
    assert sessions[0].check == check
    assert sessions[0].state == NEEDS_QUIZ


def test_check_photo_must_be_after_end() -> None:
    start, end = _p("a", 10, 0), _p("b", 30, 40)
    page = _sessions.check_page_for(start, end)
    same_time = _p("c", page, 40)
    sessions = _sessions.build_sessions([start, end, same_time])
    assert sessions[0].check is None
    assert sessions[0].state == NEEDS_CHECK


def test_one_page_session_needs_no_check() -> None:
    sessions = _sessions.build_sessions([_p("a", 10, 0), _p("b", 11, 2)])
    assert sessions[0].check_page is None
    assert sessions[0].state == NEEDS_QUIZ


def test_backwards_photo_replaces_start() -> None:
    photos = [_p("a", 50, 0), _p("b", 50, 1), _p("c", 10, 2), _p("d", 12, 5)]
    sessions = _sessions.build_sessions(photos)
    assert [(s.start.name, s.end.name) for s in sessions] == [("c", "d")]


def test_stale_start_replaced() -> None:
    photos = [_p("a", 10, 0), _p("b", 20, 6 * 60 + 1), _p("c", 22, 6 * 60 + 5)]
    sessions = _sessions.build_sessions(photos)
    assert [(s.start.name, s.end.name) for s in sessions] == [("b", "c")]
    # Exactly MAX_SESSION is still one session.
    edge = _sessions.build_sessions([_p("a", 10, 0), _p("b", 20, 6 * 60)])
    assert len(edge) == 1


def test_check_claimed_by_right_pending_session() -> None:
    s1 = (_p("a", 10, 0), _p("b", 20, 30))
    s2 = (_p("c", 100, 60), _p("d", 120, 90))
    page1 = _sessions.check_page_for(*s1)
    page2 = _sessions.check_page_for(*s2)
    assert page1 != page2
    photos = [*s1, *s2, _p("e", page2, 91), _p("f", page1, 92)]
    sessions = _sessions.build_sessions(photos)
    assert [s.check.name if s.check else None for s in sessions] == ["f", "e"]
    # A second photo of an already-answered check page opens a new start.
    again = _sessions.build_sessions([*photos, _p("g", page1, 93)])
    assert len(again) == 2
    assert _sessions.open_start([*photos, _p("g", page1, 93)]) == _p("g", page1, 93)


def test_open_start() -> None:
    assert _sessions.open_start([]) is None
    start = _p("a", 10, 0)
    assert _sessions.open_start([start]) == start
    end = _p("b", 30, 40)
    assert _sessions.open_start([start, end]) is None
    page = _sessions.check_page_for(start, end)
    assert _sessions.open_start([start, end, _p("c", page, 41)]) is None
    later = _p("d", 31, 50)
    assert _sessions.open_start([start, end, later]) == later


def test_open_start_ignores_stale_leftovers() -> None:
    # "a" was replaced as a start by "b" and never closed; the newest photo
    # ("c") ends b's session, so nothing is waiting for an end photo.
    photos = [_p("a", 50, 0), _p("b", 10, 1), _p("c", 11, 5)]
    assert _sessions.open_start(photos) is None
