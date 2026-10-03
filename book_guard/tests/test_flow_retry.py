# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""One rewrite per session: a failed summary is graded once more, then final."""

from __future__ import annotations

from typing import TYPE_CHECKING

from book_guard import _grading, _ledger, _quiz, _retime
from book_guard._ledger import CREDIT
from book_guard._quiz import MIN_SUMMARY_CHARS, Verdict
from book_guard._render import session_line, todo_lines
from book_guard._session_files import detail
from book_guard._sessions import NEEDS_QUIZ
from book_guard._state import CREDITED, FAILED, awaiting_quiz, snapshot
from book_guard._state_json import to_json
from book_guard.tests._flow_helpers import (
    LOCKED_DAY,
    T0,
    only_session,
    quiz_pair,
    rec,
    seed_photos,
)

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths
    from book_guard._state import SessionView

SUMMARY = "x" * MIN_SUMMARY_CHARS
REWRITE_NOTE = " You may rewrite this summary once; the second verdict is final."


def _grader(monkeypatch: pytest.MonkeyPatch, *results: bool) -> None:
    answers = iter(results)

    def grade(*_args: object, **_kwargs: object) -> Verdict:
        return Verdict(passed=next(answers), feedback="Name events.")

    monkeypatch.setattr(_grading, "grade", grade)


def _view(paths: Paths) -> SessionView:
    (view,) = snapshot(paths, today=LOCKED_DAY).sessions
    return view


def test_a_failed_summary_gets_one_rewrite_then_is_final(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seed_photos(bg_paths, *quiz_pair())
    sid = _view(bg_paths).session.session_id
    _grader(monkeypatch, False, False, True)

    first = _grading.quiz_one(bg_paths, _view(bg_paths), SUMMARY)
    assert first == Verdict(passed=False, feedback="Name events." + REWRITE_NOTE)
    view = _view(bg_paths)
    assert view.status == NEEDS_QUIZ
    snap = snapshot(bg_paths, today=LOCKED_DAY)
    assert awaiting_quiz(snap) == [view]
    retry = to_json(bg_paths, snap)["sessions"][0]["retry"]
    assert (retry["feedback"], retry["summary"]) == ("Name events.", SUMMARY)
    assert retry["graded_at"]
    assert session_line(view).endswith(
        "summary failed: rewrite it once more (book-guard quiz)"
    )
    assert todo_lines(snap)[0].startswith("REWRITE THE SUMMARY at the PC for p. 10-11")

    second = _grading.quiz_one(bg_paths, view, SUMMARY)
    assert second == Verdict(passed=False, feedback="Name events.")
    final = _view(bg_paths)
    assert final.status == FAILED
    assert [e.entry_id for e in final.verdicts] == [sid, f"{sid}#2"]
    assert [e.detail["attempt"] for e in final.verdicts] == ["1", "2"]
    assert to_json(bg_paths, snapshot(bg_paths))["sessions"][0]["retry"] is None

    # A third summary is graded (the check is under the lock) but never recorded.
    third = _grading.quiz_one(bg_paths, final, SUMMARY)
    assert third == Verdict(passed=False, feedback="This session was already graded.")
    assert len(_view(bg_paths).verdicts) == 2


def test_a_passing_rewrite_is_credited_once_with_its_bonus(bg_paths: Paths) -> None:
    pair = [rec("b1", 10, T0), rec("b2", 40, T0.replace(hour=17))]
    seed_photos(bg_paths, *pair)
    session = only_session(pair)
    sid = session.session_id
    _quiz.record_verdict(bg_paths, None, session, Verdict(False, "thin"), "first")
    entry = _quiz.record_verdict(bg_paths, None, session, Verdict(True, "ok"), "two")
    assert entry is not None
    assert (entry.entry_id, entry.kind, entry.amount) == (f"{sid}#2", CREDIT, 30)
    assert (entry.detail["attempt"], entry.detail["bonus"]) == ("2", "1")
    assert entry.detail["ended_at"] == str(int(session.ended_at.timestamp()))
    again = _quiz.record_verdict(bg_paths, None, session, Verdict(True, "x"), "3")
    assert again is None

    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert [e.amount for e in ledger.of_kind(CREDIT)] == [30]
    view = _view(bg_paths)
    assert view.status == CREDITED
    assert (detail(view)["feedback"], detail(view)["summary"]) == ("ok", "two")
    assert to_json(bg_paths, snapshot(bg_paths))["sessions"][0]["retry"] is None


def test_a_session_graded_once_keeps_its_times(bg_paths: Paths) -> None:
    seed_photos(bg_paths, *quiz_pair())
    session = _view(bg_paths).session
    _quiz.record_verdict(bg_paths, None, session, Verdict(False, "thin"), "first")
    response = _retime.set_times(
        bg_paths, {"session_id": session.session_id, "start": T0.isoformat()}
    )
    assert response.message == "This session was already graded."
