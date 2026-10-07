# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The snapshot as text: session lines, to-dos and the full status."""

from __future__ import annotations

import dataclasses
from datetime import timedelta

import pytest

from book_guard._render import session_line, status_lines, todo_lines
from book_guard._sessions import NEEDS_CHECK, NEEDS_QUIZ, TOO_FAST
from book_guard._state import CREDITED, SessionView
from book_guard.tests._flow_helpers import (
    T0,
    check_pair,
    fast_pair,
    make_book,
    make_snap,
    only_session,
    quiz_pair,
    rec,
)

WHEN = T0.astimezone().strftime("%a %d.%m %H:%M")
CHECK = only_session(check_pair())
TODAY = "Today: 0/20 pages (not yet: 20 pages a day open the lock even when behind)"


@pytest.mark.parametrize(
    ("status", "action"),
    [
        (NEEDS_CHECK, f"photograph page {CHECK.check_page}"),
        (NEEDS_QUIZ, "write the summary at the PC (book-guard quiz)"),
        (TOO_FAST, "not counted: under 50 s per page"),
        (CREDITED, "credited"),
        ("mystery", "mystery"),
    ],
)
def test_session_line_every_status(status: str, action: str) -> None:
    line = session_line(SessionView(CHECK, None, status))
    assert line == f"p. 10-20 (10 p, 20 min) {WHEN} -- {action}"


def test_todo_lines_empty_when_nothing_pending() -> None:
    assert todo_lines(make_snap(book=make_book())) == []


def test_todo_lines_all_kinds_in_urgency_order() -> None:
    quiz = only_session(quiz_pair("q", T0 + timedelta(hours=1)))
    start = rec("open", 50, T0 + timedelta(hours=2))
    snap = make_snap(
        sessions=[
            SessionView(quiz, None, NEEDS_QUIZ),
            SessionView(CHECK, None, NEEDS_CHECK),
            SessionView(only_session(fast_pair()), None, TOO_FAST),
        ],
        open_start=start,
    )
    since = start.taken.astimezone().strftime("%a %H:%M")
    assert todo_lines(snap) == [
        f"TAKE A PHOTO of page {CHECK.check_page} (check for p. 10-20)",
        "WRITE A SUMMARY at the PC for p. 10-11",
        f"Reading since p. 50 ({since}) -- photograph the page where you stop",
        (
            "No book registered: search it in the app's Book tab, or photograph "
            "the barcode"
        ),
    ]


def test_status_lines_locked_with_everything() -> None:
    views = [SessionView(CHECK, None, NEEDS_CHECK)] * 8
    snap = make_snap(book=make_book(), sessions=views, locked=True)
    lines = status_lines(snap, recent=3)
    assert lines[:6] == [
        "LOCKED: 12 pages behind",
        "Book: War -- Tol, last page 300",
        (
            "October 2026: 12/300 pages (pace line today: 40; carried debt 5; "
            "books finished 1)"
        ),
        TODAY,
        "Debt: 28 pages, carried into next month",
        "Escapes left this month: 2",
    ]
    assert lines[6:8] == ["", "Next:"]
    assert lines.count("Recent sessions:") == 1
    assert len(lines) == 6 + 2 + 8 + 2 + 3


def test_status_lines_quiet() -> None:
    lines = status_lines(make_snap(book=make_book(pages=None, author="")))
    assert lines == [
        "unlocked: on pace",
        "Book: War",
        (
            "October 2026: 12/300 pages (pace line today: 40; carried debt 5; "
            "books finished 1)"
        ),
        TODAY,
        "Debt: 28 pages, carried into next month",
        "Escapes left this month: 2",
    ]


def test_status_lines_show_the_daily_pass_and_debt_share() -> None:
    pace = dataclasses.replace(make_snap().pace, pages_today=20, days_left=5)
    lines = status_lines(dataclasses.replace(make_snap(), pace=pace))
    assert lines[3:5] == [
        "Today: 20/20 pages (passed: 20 pages a day open the lock even when behind)",
        "Debt: 28 pages = 6/day over the 5 counted days left this month",
    ]


def test_status_lines_on_pace_show_no_debt() -> None:
    pace = dataclasses.replace(make_snap().pace, pages=40)
    lines = status_lines(dataclasses.replace(make_snap(), pace=pace))
    assert lines[3:5] == [TODAY, "Escapes left this month: 2"]


def test_status_lines_without_a_book() -> None:
    lines = status_lines(make_snap())
    assert lines[1] == "Book: (none)"
    assert lines[-1].startswith("  * No book registered")


def test_status_lines_show_carried_credit() -> None:
    snap = dataclasses.replace(
        make_snap(), pace=dataclasses.replace(make_snap().pace, carried_credit=80)
    )
    assert (
        "carried debt 5; carried credit 80; books finished 1" in (status_lines(snap)[2])
    )
