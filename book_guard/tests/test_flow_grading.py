# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Registering books and grading summaries (_grading and _quiz)."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _grading, _ledger, _quiz
from book_guard._http import UnavailableError
from book_guard._ledger import CREDIT, REJECT
from book_guard._openlibrary import BookInfo
from book_guard._quiz import MIN_SUMMARY_CHARS, Verdict
from book_guard._state import SessionView
from book_guard.tests._flow_helpers import (
    ISBN13,
    T0,
    add_book,
    check_pair,
    make_book,
    only_session,
    quiz_pair,
    rec,
    seed_photos,
)

if TYPE_CHECKING:
    from book_guard._paths import Paths

SUMMARY = "x" * MIN_SUMMARY_CHARS


def _lookup(result: BookInfo | None) -> Any:
    return lambda _paths, _isbn: result


# -- register_isbn ----------------------------------------------------------


def test_register_isbn_offline(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    def offline(_paths: Paths, _isbn: str) -> None:
        msg = "no book source answered"
        raise UnavailableError(msg)

    monkeypatch.setattr(_grading, "lookup_book", offline)
    assert _grading.register_isbn(bg_paths, ISBN13) == (
        False,
        "No book source reachable (no book source answered); try again later",
    )
    assert not bg_paths.ledger.exists()


def test_register_unknown_isbn_asks_for_pages(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(_grading, "lookup_book", _lookup(None))
    tail = "set the last page of your copy (app, or: book-guard pages N)"
    assert _grading.register_isbn(bg_paths, ISBN13) == (
        True,
        f"Now reading: ISBN {ISBN13}; {tail}",
    )
    named = _grading.register_isbn(bg_paths, ISBN13, title="Cesarz", author="Sher")
    assert named == (True, f"Now reading: Cesarz -- Sher; {tail}")


def test_register_with_pages_override(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    info = BookInfo(title="War", author="Tol", pages=900, isbn=ISBN13)
    monkeypatch.setattr(_grading, "lookup_book", _lookup(info))
    assert _grading.register_isbn(bg_paths, ISBN13) == (
        True,
        "Now reading: War -- Tol, last page 900",
    )
    _ok, message = _grading.register_isbn(bg_paths, ISBN13, pages=1225)
    assert message.endswith("page 1225")


# -- quiz_one ---------------------------------------------------------------


@pytest.mark.parametrize("with_book", [True, False])
def test_quiz_one_records_and_guards_regrading(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, *, with_book: bool
) -> None:
    records = quiz_pair()
    seed_photos(bg_paths, *records)
    book = add_book(bg_paths) if with_book else None
    view = SessionView(only_session(records), book, "needs-quiz")
    seen: list[dict[str, object]] = []

    def grade(*args: object, **kwargs: object) -> Verdict:
        seen.append({"args": args, **kwargs})
        return Verdict(passed=True, feedback="Well read.")

    monkeypatch.setattr(_grading, "grade", grade)
    assert _grading.quiz_one(bg_paths, view, SUMMARY, model="sonnet") == Verdict(
        passed=True, feedback="Well read."
    )
    assert seen[0]["model"] == "sonnet"
    assert seen[0]["span"] == ""  # no book file attached
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert ledger.has(view.session.session_id)
    assert bg_paths.next_file.exists()

    again = _grading.quiz_one(bg_paths, view, SUMMARY)
    assert again == Verdict(passed=False, feedback="This session was already graded.")
    assert len(ledger.of_kind(CREDIT)) == 1


# -- _quiz ------------------------------------------------------------------


def test_short_summary_fails_without_a_model_call(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(_quiz, "ask", None)
    verdict = _quiz.grade(None, only_session(quiz_pair()), "  too short  ")
    assert verdict == Verdict(
        passed=False,
        feedback=f"Write at least {MIN_SUMMARY_CHARS} characters (3-5 sentences).",
    )


@pytest.mark.parametrize(
    ("answer", "expected"),
    [
        ({"passed": True, "feedback": "Good."}, Verdict(passed=True, feedback="Good.")),
        ({"passed": "true", "feedback": None}, Verdict(passed=False, feedback="")),
        ({}, Verdict(passed=False, feedback="")),
    ],
)
def test_grade_parses_the_answer(
    monkeypatch: pytest.MonkeyPatch, answer: dict[str, object], expected: Verdict
) -> None:
    calls: list[tuple[str, str, str]] = []

    def ask(system: str, prompt: str, *, model: str) -> dict[str, object]:
        calls.append((system, prompt, model))
        return answer

    monkeypatch.setattr(_quiz, "ask", ask)
    session = only_session(quiz_pair())
    assert _quiz.grade(make_book(), session, SUMMARY, model="opus", span="S") == (
        expected
    )
    assert calls[0][2] == "opus"
    assert "--- the book's own text" in calls[0][1]


def test_build_prompt_with_book_and_span() -> None:
    session = only_session(quiz_pair(text="It was a dark night."))
    prompt = _quiz.build_prompt(make_book(), session, f"  {SUMMARY}  ", span="SPAN")
    assert prompt.startswith(f"Book: War -- Tol (ISBN {ISBN13}).")
    assert "pages 10-11 (1 pages) in 5 minutes" in prompt
    assert "--- page 10 ---\nIt was a dark night." in prompt
    assert "\nSPAN\n" in prompt
    assert "consistent with the book's text above" in prompt
    assert f"\n{SUMMARY}\n---\n" in prompt


def test_build_prompt_without_book_or_span() -> None:
    prompt = _quiz.build_prompt(None, only_session(quiz_pair()), SUMMARY)
    assert prompt.startswith("Book: an unregistered book (ISBN unknown).")
    assert "--- page 11 ---\n(no legible text)" in prompt
    assert "the book's own text" not in prompt
    assert "if you know this book" in prompt


@pytest.mark.parametrize(
    ("pair", "eligible"),
    [
        (check_pair(), False),
        (quiz_pair(), False),
        ([rec("b1", 10, T0), rec("b2", 40, T0.replace(hour=17))], True),
    ],
)
def test_bonus_needs_pages_and_minutes(pair: list[Any], *, eligible: bool) -> None:
    assert _quiz.bonus_eligible(only_session(pair)) is eligible


def test_record_verdict_credit_row(bg_paths: Paths) -> None:
    big = only_session([rec("b1", 10, T0), rec("b2", 40, T0.replace(hour=17))])
    assert _quiz.bonus_eligible(big)
    entry = _quiz.record_verdict(
        bg_paths, make_book(), big, Verdict(True, "f" * 2000), " sum "
    )
    assert (entry.kind, entry.amount, entry.day) == (
        CREDIT,
        30,
        big.end.taken.astimezone().date().isoformat(),
    )
    assert entry.detail["bonus"] == "1"
    assert entry.detail["isbn"] == ISBN13
    assert entry.detail["check_page"] == str(big.check_page)
    assert len(entry.detail["feedback"]) == 1500
    assert entry.detail["summary"] == "sum"
    assert entry.detail["ended_at"] == str(int(big.end.taken.timestamp()))
    assert _ledger.load(bg_paths.ledger, bg_paths.key_file).has(big.session_id)


def test_record_verdict_reject_row(bg_paths: Paths) -> None:
    session = only_session(quiz_pair())
    entry = _quiz.record_verdict(bg_paths, None, session, Verdict(False, "no"), "s")
    assert (entry.kind, entry.amount) == (REJECT, 0)
    assert entry.detail["bonus"] == "0"
    assert entry.detail["isbn"] == entry.detail["title"] == ""
    assert entry.detail["check_page"] == ""
