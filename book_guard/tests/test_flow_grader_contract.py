# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The grader's contract: a fail says what to add; an outage never blocks."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

import pytest

from book_guard import _grader_wait, _grading, _ledger
from book_guard._atomic_json import write_json
from book_guard._claude import ClaudeUnavailableError
from book_guard._constants import GRADER_GRACE
from book_guard._grader_wait import clock_file
from book_guard._ledger import CREDIT
from book_guard._prompt import Context, build_prompt
from book_guard._quiz import MIN_SUMMARY_CHARS, Verdict
from book_guard._state import CREDITED, snapshot
from book_guard._state_json import to_json
from book_guard.tests._flow_helpers import (
    T0,
    only_session,
    quiz_pair,
    rec,
    seed_photos,
)

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._state import SessionView

SUMMARY = "x" * MIN_SUMMARY_CHARS
MISSING = ("what he did in the village", "who he worked for")


def _view(paths: Paths) -> SessionView:
    (view,) = snapshot(paths).sessions
    return view


def test_a_rewrite_is_judged_on_the_checklist_only() -> None:
    session = only_session(quiz_pair())
    prompt = build_prompt(None, session, SUMMARY, Context(checklist=MISSING))
    assert "This is a REWRITE" in prompt
    assert "\n- what he did in the village\n- who he worked for\n" in prompt
    assert "Do not add requirements beyond this list" in prompt
    assert "Judge it generously" in prompt
    assert "never fail for anything you cannot verify" in prompt
    assert "is NOT covered when the rewrite only names it" in prompt
    assert "STEP 1" not in prompt
    fresh = build_prompt(None, session, SUMMARY)
    assert 'list in "missing" 1-3 things' in fresh
    assert "never the answer itself" in fresh
    assert "STEP 1, the photo test" in fresh
    assert "REWRITE" not in fresh


def test_what_the_grader_cannot_check_is_never_a_reason_to_fail() -> None:
    session = only_session(quiz_pair())
    plain = build_prompt(None, session, SUMMARY)
    assert "ONLY 2 photographed pages, not the 1 pages the reader read" in plain
    assert "is NEVER a reason to fail" in plain
    assert "Your own memory of the book is not evidence" in plain
    with_text = build_prompt(None, session, SUMMARY, Context(span="BOOK TEXT"))
    assert "may be another edition or language" in with_text
    assert "ONLY 2 photographed" not in with_text
    assert "is NEVER a reason to fail" in with_text


def test_a_fail_names_what_to_add_and_the_rewrite_gets_it(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seed_photos(bg_paths, *quiz_pair())
    seen: list[Context] = []
    verdicts = iter(
        [Verdict(False, "Too thin.", MISSING), Verdict(True, "Covered both.")]
    )

    def grade(*_args: object, context: Context, **_kwargs: object) -> Verdict:
        seen.append(context)
        return next(verdicts)

    monkeypatch.setattr(_grading, "grade", grade)
    first = _grading.quiz_one(bg_paths, _view(bg_paths), SUMMARY)
    assert first.feedback == (
        "Too thin. To be accepted, add: what he did in the village; who he "
        "worked for. Rewrite the summary and send it again."
    )
    assert seen[0].checklist == ()
    retry = to_json(bg_paths, snapshot(bg_paths))["sessions"][0]["retry"]
    assert retry["missing"] == list(MISSING)

    second = _grading.quiz_one(bg_paths, _view(bg_paths), SUMMARY)
    assert second == Verdict(True, "Covered both.")
    assert seen[1].checklist == MISSING
    assert _view(bg_paths).status == CREDITED


def test_every_fail_says_what_was_missing(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seed_photos(bg_paths, *quiz_pair())
    monkeypatch.setattr(
        _grading, "grade", lambda *_a, **_k: Verdict(False, "No.", MISSING[:1])
    )
    expected = (
        "No. To be accepted, add: what he did in the village."
        " Rewrite the summary and send it again."
    )
    for _ in range(3):
        again = _grading.quiz_one(bg_paths, _view(bg_paths), SUMMARY)
        assert again.feedback == expected


def _down(*_args: object, **_kwargs: object) -> Verdict:
    msg = "usage limit reached"
    raise ClaudeUnavailableError(msg)


def test_an_hour_of_grader_outage_credits_ungraded_with_the_bonus(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    pair = [rec("b1", 10, T0), rec("b2", 40, T0.replace(hour=17))]
    seed_photos(bg_paths, *pair)
    view = _view(bg_paths)
    sid = view.session.session_id
    monkeypatch.setattr(_grading, "grade", _down)
    with pytest.raises(ClaudeUnavailableError):
        _grading.quiz_one(bg_paths, view, SUMMARY)  # starts the clock
    assert sid in clock_file(bg_paths).read_text(encoding="utf-8")
    assert not _ledger.load(bg_paths.ledger, bg_paths.key_file).entries

    long_ago = datetime.now(tz=UTC) - GRADER_GRACE - timedelta(minutes=1)
    write_json(clock_file(bg_paths), {sid: long_ago.isoformat()})
    verdict = _grading.quiz_one(bg_paths, view, SUMMARY)
    assert (verdict.passed, verdict.feedback) == (True, _grading.UNGRADED)
    (entry,) = _ledger.load(bg_paths.ledger, bg_paths.key_file).of_kind(CREDIT)
    assert (entry.amount, entry.detail["graded"], entry.detail["bonus"]) == (
        30,
        "0",
        "1",
    )
    assert clock_file(bg_paths).read_text(encoding="utf-8").strip() == "{}"


def test_a_graded_summary_stops_the_clock(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seed_photos(bg_paths, *quiz_pair())
    view = _view(bg_paths)
    write_json(clock_file(bg_paths), {view.session.session_id: T0.isoformat()})
    monkeypatch.setattr(_grading, "grade", lambda *_a, **_k: Verdict(True, "ok"))
    _grading.quiz_one(bg_paths, view, SUMMARY)
    entry = _ledger.load(bg_paths.ledger, bg_paths.key_file).entries[0]
    assert entry.detail["graded"] == "1"
    assert _grader_wait.waited_out(bg_paths, "other", now=T0) is False


@pytest.mark.parametrize("content", ["not json", "[1, 2]"])
def test_a_torn_clock_restarts(bg_paths: Paths, content: str) -> None:
    clock_file(bg_paths).parent.mkdir(parents=True, exist_ok=True)
    clock_file(bg_paths).write_text(content, encoding="utf-8")
    assert _grader_wait.waited_out(bg_paths, "s", now=T0) is False
    later = T0 + GRADER_GRACE
    assert _grader_wait.waited_out(bg_paths, "s", now=later) is True
    _grader_wait.stop(bg_paths, "absent")  # nothing to forget: no write
    _grader_wait.stop(bg_paths, "s")
    assert _grader_wait.waited_out(bg_paths, "s", now=later) is False


def test_short_summaries_never_wait_out_an_outage(bg_paths: Paths) -> None:
    """The length check needs no model, so a short summary fails at once."""
    seed_photos(bg_paths, *quiz_pair())
    verdict = _grading.quiz_one(bg_paths, _view(bg_paths), "too short")
    assert not verdict.passed
    assert not clock_file(bg_paths).exists()
