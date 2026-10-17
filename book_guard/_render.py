# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The snapshot as plain text: the CLI status, NEXT.txt and the lock body.

Today's line shows the day's requirement (reaching it earns the +1h bonus)
apart from the 20-page lock pass, which clears the lock and earns nothing.
On a sick day it says so: nothing is asked, and the pages that would have
been asked still earn the bonus.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Final

from book_guard._constants import DAILY_PASS_PAGES, WEEKEND_CAP_PAGES
from book_guard._sessions import NEEDS_CHECK, NEEDS_QUIZ, TOO_FAST
from book_guard._state import CREDITED

if TYPE_CHECKING:
    from book_guard._pace import Pace
    from book_guard._state import SessionView, Snapshot


_STATUS_TEXT: Final = {
    NEEDS_CHECK: "photograph page {check}",
    NEEDS_QUIZ: "write the summary at the PC (book-guard quiz)",
    TOO_FAST: "not counted: under 50 s per page",
    CREDITED: "credited",
}


_EARN: Final = "reaching it earns the +1h bonus"


def session_line(view: SessionView) -> str:
    """``p. 40-65 (25 p, 31 min) Sat 21:04 -- photograph page 52``."""
    s = view.session
    when = s.started_at.astimezone().strftime("%a %d.%m %H:%M")
    action = _STATUS_TEXT.get(view.status, view.status).format(check=s.check_page)
    if view.status == NEEDS_QUIZ and view.verdicts:
        action = "summary failed: rewrite it (book-guard quiz)"
    span = f"p. {s.start.page}-{s.end.page} ({s.pages} p, {s.minutes} min)"
    return f"{span} {when} -- {action}"


def todo_lines(snap: Snapshot) -> list[str]:
    """What to do next, most urgent first. Empty when nothing is pending."""
    lines = [
        f"TAKE A PHOTO of page {v.session.check_page} "
        f"(check for p. {v.session.start.page}-{v.session.end.page})"
        for v in snap.with_status(NEEDS_CHECK)
    ]
    lines += [
        f"{'REWRITE THE' if v.verdicts else 'WRITE A'} SUMMARY at the PC for "
        f"p. {v.session.start.page}-{v.session.end.page}"
        for v in snap.with_status(NEEDS_QUIZ)
    ]
    if snap.open_start is not None:
        taken = snap.open_start.taken.astimezone().strftime("%a %H:%M")
        lines.append(
            f"Reading since p. {snap.open_start.page} ({taken}) -- "
            "photograph the page where you stop"
        )
    if snap.book is None:
        lines.append(
            "No book registered: search it in the app's Book tab, or "
            "photograph the barcode"
        )
    return lines


def _today_line(p: Pace, *, sick: bool) -> str:
    """Today's requirement and whether its +1h bonus is in."""
    if sick:
        earned = "bonus earned" if p.ask.bonus else f"{p.ask.bonus_at} earn the +1h"
        return (
            f"Today is a sick day: no pages asked, its share is dropped "
            f"({p.pages_today} read; {earned})"
        )
    if not p.ask.required and p.ask.bonus:
        return "Today asks no pages: the +1h bonus is granted without reading"
    return (
        f"Today: {p.pages_today}/{p.ask.required} pages, today's requirement "
        f"({'bonus earned' if p.ask.bonus else _EARN})"
    )


def _debt_line(p: Pace) -> str:
    """Where the debt goes: onto the weekends left, what fits nowhere carried."""
    if not p.ask.debt_per_day:
        return f"Debt: {p.behind} pages, carried into next month"
    line = (
        f"Debt: {p.behind} pages = up to {p.ask.debt_per_day}/day over the "
        f"{p.ask.debt_days} weekend days left (Sat/Sun, at most "
        f"{WEEKEND_CAP_PAGES} a day)"
    )
    if p.ask.debt_unplaced:
        line += f"; {p.ask.debt_unplaced} carried into next month"
    return line


def status_lines(snap: Snapshot, *, recent: int = 6) -> list[str]:
    """The full human-readable status."""
    p = snap.pace
    book = snap.book.label if snap.book else "(none)"
    last = f", last page {snap.book.pages}" if snap.book and snap.book.pages else ""
    lines = [
        f"{'LOCKED' if snap.locked else 'unlocked'}: {snap.reason}",
        f"Book: {book}{last}",
        (
            f"{p.month:%B %Y}: {p.pages}/{p.target} pages "
            f"({'line tonight' if p.ask.daily else 'pace line today'}: {p.required}; "
            f"carried debt {p.carried_debt}; "
            f"{f'carried credit {p.carried_credit}; ' if p.carried_credit else ''}"
            f"books finished {p.finished_books})"
        ),
        _today_line(p, sick=snap.sick_today),
    ]
    if p.ask.excused:
        lines.append(f"Sick days excused: {p.ask.excused} pages off the target")
    if p.ask.daily:
        if p.ask.debt_unplaced:
            lines.append(
                f"Debt: {p.ask.debt_unplaced} pages no day left can hold, "
                "carried into next month"
            )
    else:
        lines.append(
            f"Lock pass: {p.pages_today}/{DAILY_PASS_PAGES} pages "
            f"({'passed' if p.passed_today else 'not yet'}: "
            f"{DAILY_PASS_PAGES} pages a day open the lock even when behind)"
        )
        if p.behind:
            lines.append(_debt_line(p))
    lines.append(f"Escapes left this month: {snap.escapes_left}")
    todo = todo_lines(snap)
    if todo:
        lines += ["", "Next:", *(f"  * {t}" for t in todo)]
    if snap.sessions:
        lines += ["", "Recent sessions:"]
        lines += [f"  {session_line(v)}" for v in snap.sessions[-recent:]]
    return lines
