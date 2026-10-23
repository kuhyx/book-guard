# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""In-app reading: graded on the text on screen, credited, and where it leaves the reader."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

import pytest

from book_guard import (
    _ebook_sessions,
    _ledger,
    _local,
    _quiz,
)
from book_guard._anchor import find_span
from book_guard._app_handlers import HANDLERS
from book_guard._claude import ClaudeUnavailableError
from book_guard._library import write_library
from book_guard._library_text import book_detail
from book_guard._photo_context import context_for
from book_guard._photos import load as load_photos
from book_guard._prompt import LOCAL_REMINDER
from book_guard._requests import handle_requests
from book_guard._state import snapshot
from book_guard._state_json import to_json
from book_guard.tests._ebook_flow import (
    NOW,
    SUMMARY,
    ebook_request,
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


def test_the_grader_reads_exactly_the_text_on_screen(
    mapped: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    assert send_session(mapped).ok
    prompts: list[str] = []

    def ask(_system: str, prompt: str, *, model: str) -> dict[str, object]:
        del model
        prompts.append(prompt)
        return {"passed": True, "feedback": "Good."}

    monkeypatch.setattr(_quiz, "ask", ask)
    (view,) = snapshot(mapped).sessions
    span = find_span(mapped, ISBN13, view.session)
    assert span.text == TEXT[middle(40) : middle(52)]
    assert span.reason == "read in the app"
    response = HANDLERS["summary"](
        mapped, {"session_id": view.session.session_id, "summary": SUMMARY}
    )
    assert response.passed is True
    assert "e-book reader app" in prompts[0]
    assert "STEP 1, the photo test" not in prompts[0]
    assert TEXT[middle(40) : middle(52)] in prompts[0]
    ledger = _ledger.load(mapped.ledger, mapped.key_file)
    (row,) = ledger.verdicts()["session:ebook-abcdef0123456789"]
    assert row.amount == 12
    assert row.detail["source"] == "ebook"
    assert row.detail["estimated"] == "1"
    assert row.detail["start_offset"] == str(middle(40))
    assert row.detail["end_offset"] == str(middle(52))
    assert row.detail["check_page"] == ""
    assert snapshot(mapped).sessions[0].status == "credited"


def test_the_local_grader_gets_no_photo_reminder(
    mapped: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    assert send_session(mapped).ok
    seen: list[str] = []

    def down(*_a: object, **_k: object) -> object:
        msg = "outage"
        raise ClaudeUnavailableError(msg)

    def local(_system: str, prompt: str) -> dict[str, object]:
        seen.append(prompt)
        return {"passed": True, "feedback": "ok"}

    monkeypatch.setattr(_quiz, "ask", down)
    monkeypatch.setattr(_local, "ask_local", local)
    monkeypatch.setattr("book_guard._errlog.claude_ok", lambda _p: None)
    (view,) = snapshot(mapped).sessions
    assert _quiz.grade(view.book, view.session, SUMMARY).passed
    assert LOCAL_REMINDER not in seen[0]


def test_a_summary_queued_with_its_session_is_graded_in_the_same_pass(
    mapped: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        _quiz, "ask", lambda *_a, **_k: {"passed": True, "feedback": "Good."}
    )
    mapped.requests.mkdir(parents=True, exist_ok=True)
    # Request ids are random: the summary's may sort first.
    summary = {
        "id": "aaaaaaaa01",
        "type": "summary",
        "session_id": "session:ebook-abcdef0123456789",
        "summary": SUMMARY,
    }
    session = ebook_request(id="ffffffff01")
    for body in (summary, session):
        (mapped.requests / f"{body['id']}.json").write_text(json.dumps(body))
    assert handle_requests(mapped, HANDLERS) == 2
    answer = json.loads((mapped.responses / "aaaaaaaa01.json").read_text())
    assert answer["passed"] is True


def test_the_library_lists_the_app_session(mapped: Paths) -> None:
    assert send_session(mapped).ok
    write_library(mapped, snapshot(mapped))
    library = json.loads(mapped.library_file.read_text("utf-8"))
    (book,) = library["books"]
    (session,) = book["sessions"]
    assert session["id"] == "session:ebook-abcdef0123456789"
    assert session["photos"] == []
    assert session["source"] == "ebook"
    assert session["estimated"] is True
    assert any("≈ p. 40-52 (12 p, 60 min)" in line for line in book_detail(book))


# -- the physical position moves on -----------------------------------------


def test_a_start_photo_after_app_reading_is_read_near_its_end(
    mapped: Paths,
) -> None:
    assert send_session(mapped).ok
    ledger = _ledger.load(mapped.ledger, mapped.key_file)
    context = context_for(
        "start_x.jpg",
        NOW,
        load_photos(mapped.photos),
        ledger,
        _ebook_sessions.sessions(mapped),
    )
    assert context.near == 52


def test_the_latest_page_follows_app_reading(mapped: Paths) -> None:
    assert send_session(mapped).ok
    state = to_json(mapped, snapshot(mapped))
    assert state["book"]["latest_page"] == 52
