# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""In-app reading: the ebook_session request, checked and stored."""

from __future__ import annotations

from datetime import timedelta
import json
from typing import TYPE_CHECKING

import pytest

from book_guard import (
    _ebook_sessions,
)
from book_guard._constants import MAX_SESSION
from book_guard._render import session_line, todo_lines
from book_guard._session_files import detail
from book_guard._sessions import NEEDS_QUIZ, TOO_FAST
from book_guard._state import snapshot
from book_guard._state_json import to_json
from book_guard.tests._ebook_flow import (
    NOW,
    map_book,
    send_session,
)
from book_guard.tests._ebook_helpers import TEXT, middle
from book_guard.tests._flow_helpers import ISBN13

if TYPE_CHECKING:
    from book_guard._paths import Paths


@pytest.fixture
def mapped(bg_paths: Paths) -> Paths:
    """A registered book with its ebook indexed, five pages photographed."""
    return map_book(bg_paths)


def test_a_session_read_in_the_app_waits_for_its_summary(mapped: Paths) -> None:
    response = send_session(mapped)
    assert response.ok, response.message
    assert "≈ p. 40-52 (12 pages)" in response.message
    (view,) = snapshot(mapped).sessions
    s = view.session
    assert s.session_id == "session:ebook-abcdef0123456789"
    assert (s.start.page, s.end.page, s.pages) == (40, 52, 12)
    assert s.estimated
    assert s.evidence == []
    assert view.status == NEEDS_QUIZ
    assert view.book is not None
    assert view.book.isbn == ISBN13
    listed = to_json(mapped, snapshot(mapped))["sessions"][0]
    assert listed["source"] == "ebook"
    assert listed["estimated"] is True
    assert listed["check_page"] is None
    doc = detail(view)
    assert doc["photos"] == []
    assert doc["source"] == "ebook"
    assert session_line(view).startswith("≈ p. 40-52 (12 p, 60 min)")
    assert "WRITE A SUMMARY at the PC for ≈ p. 40-52" in todo_lines(snapshot(mapped))


def test_the_session_is_stored_append_only(mapped: Paths) -> None:
    assert send_session(mapped).ok
    again = send_session(mapped)  # the outbox may send it twice
    assert again.ok
    assert "already" in again.message
    assert len(_ebook_sessions.load(mapped)) == 1
    stored = json.loads(mapped.ebook_sessions.read_text("utf-8"))
    assert stored["sessions"][0]["start_page"] == 40


@pytest.mark.parametrize(
    ("over", "said"),
    [
        ({"session": "../x"}, "session id"),
        ({"isbn": "9780000000002"}, "no page map"),
        ({"text_sha": "0" * 64}, "text changed"),
        ({"start_offset": "x"}, "offsets"),
        ({"end_offset": len(TEXT) + 5}, "offsets"),
        ({"end_offset": middle(40)}, "offsets"),
        ({"started_at": "yesterday"}, "times"),
        ({"started_at": "2026-10-20T10:00:00"}, "times"),
        ({"started_at": (NOW - timedelta(minutes=30)).isoformat()}, "times"),
        ({"started_at": (NOW - MAX_SESSION - timedelta(hours=2)).isoformat()}, "6 h"),
        ({"ended_at": (NOW + timedelta(hours=1)).isoformat()}, "future"),
        (
            {
                "started_at": (NOW - timedelta(days=8, hours=1)).isoformat(),
                "ended_at": (NOW - timedelta(days=8)).isoformat(),
            },
            "7 days",
        ),
        ({"end_offset": middle(40) + 10}, "less than a page"),
    ],
)
def test_a_session_that_cannot_count_is_refused(
    mapped: Paths, over: dict[str, object], said: str
) -> None:
    response = send_session(mapped, **over)
    assert not response.ok
    assert said in response.message
    assert _ebook_sessions.load(mapped) == []


def test_the_apps_own_timestamp_format_is_accepted(mapped: Paths) -> None:
    start, end = NOW - timedelta(hours=2), NOW - timedelta(hours=1)
    response = send_session(
        mapped,
        started_at=start.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        ended_at=end.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
    )
    assert response.ok, response.message
    (view,) = snapshot(mapped).sessions
    assert view.session.started_at == start


def test_a_flipped_through_session_is_too_fast(mapped: Paths) -> None:
    response = send_session(
        mapped,
        started_at=(NOW - timedelta(minutes=65)).isoformat(),
        ended_at=(NOW - timedelta(minutes=60)).isoformat(),
    )
    assert response.ok
    (view,) = snapshot(mapped).sessions
    assert view.status == TOO_FAST


def test_sessions_are_listed_in_time_order(mapped: Paths) -> None:
    assert send_session(mapped).ok
    snap = snapshot(mapped)
    ends = [v.session.end.taken for v in snap.sessions]
    assert ends == sorted(ends)
