# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Grading when Claude is down: every vote re-cast on the local model."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

from book_guard import _local, _quiz
from book_guard._atomic_json import write_json
from book_guard._claude import ClaudeUnavailableError
from book_guard._prompt import LOCAL_REMINDER, Context
from book_guard._quiz import MIN_SUMMARY_CHARS, Verdict
from book_guard.tests._flow_helpers import make_book, only_session, quiz_pair

if TYPE_CHECKING:
    from book_guard._paths import Paths

SUMMARY = "x" * MIN_SUMMARY_CHARS


def _claude_down(*_args: object, **_kwargs: object) -> dict[str, object]:
    msg = "usage limit reached"
    raise ClaudeUnavailableError(msg)


@pytest.mark.parametrize(
    ("checklist", "reminded"), [((), True), (("what he did",), False)]
)
def test_claude_down_recasts_every_vote_locally(
    monkeypatch: pytest.MonkeyPatch, checklist: tuple[str, ...], reminded: bool
) -> None:
    """All votes go local (never a mix); only a first summary gets the reminder."""
    prompts: list[str] = []

    def local(system: str, prompt: str) -> dict[str, object]:
        prompts.append(prompt)
        return {"passed": len(prompts) != 2, "feedback": f"vote {len(prompts)}"}

    monkeypatch.setattr(_quiz, "ask", _claude_down)
    monkeypatch.setattr(_local, "ask_local", local)
    context = Context(checklist=checklist)
    verdict = _quiz.grade(
        make_book(), only_session(quiz_pair()), SUMMARY, context=context
    )
    assert (verdict.passed, verdict.feedback, verdict.votes) == (
        True,
        "vote 1",
        (True, False, True),
    )
    assert verdict.grader == f"local:{_local.LOCAL_MODEL}"
    assert len(prompts) == _quiz.GRADER_VOTES
    assert all(p.endswith(LOCAL_REMINDER) is reminded for p in prompts)


def test_record_verdict_names_the_grader(bg_paths: Paths) -> None:
    session = only_session(quiz_pair())
    verdict = Verdict(passed=True, feedback="ok", grader="local:m")
    entry = _quiz.record_verdict(bg_paths, make_book(), session, verdict, SUMMARY)
    assert entry is not None
    assert entry.detail["grader"] == "local:m"


def test_a_known_outage_skips_claude(
    monkeypatch: pytest.MonkeyPatch, bg_paths: Paths
) -> None:
    """kuhy, 2026-11-24: no Claude usage left must cost no wait at all.

    While ``claude_down.json`` names a reset still ahead, Claude is not
    asked; every vote goes local and the flag stays for the app's cue.
    """
    write_json(
        bg_paths.claude_down,
        {"since": "2026-11-26T11:57:34+01:00", "until": "2099-01-01T10:00:00+01:00"},
    )
    asked: list[str] = []
    monkeypatch.setattr(_quiz, "ask", lambda *a, **k: asked.append("claude"))
    monkeypatch.setattr(
        _local, "ask_local", lambda *_a: {"passed": True, "feedback": "ok"}
    )
    verdict = _quiz.grade(make_book(), only_session(quiz_pair()), SUMMARY)
    assert asked == []
    assert verdict.grader == f"local:{_local.LOCAL_MODEL}"
    assert bg_paths.claude_down.exists()


def test_the_first_failed_vote_stops_the_rest(monkeypatch: pytest.MonkeyPatch) -> None:
    """One vote hitting the cap is enough: the others are not waited for."""
    calls: list[int] = []

    def claude(*_args: object, **_kwargs: object) -> dict[str, object]:
        calls.append(1)
        _claude_down()
        return {}

    monkeypatch.setattr(_quiz, "ask", claude)
    monkeypatch.setattr(
        _local, "ask_local", lambda *_a: {"passed": True, "feedback": "ok"}
    )
    verdict = _quiz.grade(make_book(), only_session(quiz_pair()), SUMMARY)
    assert verdict.grader == f"local:{_local.LOCAL_MODEL}"
    assert len(calls) <= _quiz.GRADER_VOTES
