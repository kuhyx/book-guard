# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Grading runs off the photo pass (kuhy, 2026-11-24: never wait).

A summary request is left for ``book-guard-grade.service``; the photo pass
publishes its photos at once and only starts that unit.
"""

from __future__ import annotations

from datetime import UTC, datetime
import json
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _actions, _cli, _grade_pass, _grader_wait, _grading
from book_guard._claude import ClaudeUnavailableError
from book_guard._requests import Response
from book_guard._state import SessionView
from book_guard.tests._flow_helpers import only_session, quiz_pair

if TYPE_CHECKING:
    from book_guard._paths import Paths


def _put(paths: Paths, rid: str, kind: str) -> None:
    paths.requests.mkdir(parents=True, exist_ok=True)
    body = {"id": rid, "type": kind}
    (paths.requests / f"{rid}.json").write_text(json.dumps(body))


def _handlers(seen: list[str]) -> dict[str, Any]:
    def handle(_paths: Paths, request: dict[str, Any]) -> Response:
        seen.append(str(request["type"]))
        return Response(ok=True, code="ok")

    return {"summary": handle, "note": handle}


def test_the_photo_pass_leaves_summaries_and_starts_the_grader(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen: list[str] = []
    monkeypatch.setattr(_actions, "HANDLERS", _handlers(seen))
    kicked: list[str] = []
    monkeypatch.setattr(_actions, "kick", kicked.append)
    _put(bg_paths, "req-sum-0001", "summary")
    _put(bg_paths, "req-note-001", "note")
    _actions.process(bg_paths, now=1.0)
    assert seen == ["note"]
    assert (bg_paths.requests / "req-sum-0001.json").exists()
    assert kicked == [_grade_pass.GRADE_UNIT]
    assert bg_paths.next_file.exists()


def test_no_summary_no_grader(bg_paths: Paths, monkeypatch: pytest.MonkeyPatch) -> None:
    kicked: list[str] = []
    monkeypatch.setattr(_actions, "kick", kicked.append)
    _actions.process(bg_paths, now=1.0)
    assert kicked == []


def test_the_grade_pass_answers_summaries_and_publishes(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen: list[str] = []
    monkeypatch.setattr(_grade_pass, "HANDLERS", _handlers(seen))
    _put(bg_paths, "req-sum-0001", "summary")
    _put(bg_paths, "req-note-001", "note")
    _cli.main(["grade"])
    assert seen == ["summary"]
    assert (bg_paths.requests / "req-note-001.json").exists()
    assert bg_paths.next_file.exists()


def test_one_grade_pass_at_a_time(bg_paths: Paths) -> None:
    with _grade_pass.grade_lock(bg_paths) as mine:
        assert mine
        assert _grade_pass.grade_pass(bg_paths) is None


def test_the_grace_clock_starts_at_submit(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The clock runs from the grading's start, not from Claude's timeout."""
    started: list[str] = []

    def grade(*_a: object, **_k: object) -> object:
        started.extend(json.loads(_grader_wait.clock_file(bg_paths).read_text()))
        msg = "down"
        raise ClaudeUnavailableError(msg)

    monkeypatch.setattr(_grading, "grade", grade)
    view = SessionView(only_session(quiz_pair()), None, "needs-quiz")
    with pytest.raises(ClaudeUnavailableError):
        _grading.quiz_one(bg_paths, view, "x" * 200)
    assert started == [view.session.session_id]
    assert _grader_wait.waited_out(
        bg_paths, view.session.session_id, now=datetime(2099, 1, 1, tzinfo=UTC)
    )


def test_an_empty_grade_pass_publishes_nothing(bg_paths: Paths) -> None:
    assert _grade_pass.grade_pass(bg_paths) == 0
    assert not bg_paths.next_file.exists()


def test_the_grade_command_says_when_another_runs(
    bg_paths: Paths, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level("INFO")
    with _grade_pass.grade_lock(bg_paths):
        assert _cli.main(["grade"]) == 0
    assert "another grade run" in caplog.text
