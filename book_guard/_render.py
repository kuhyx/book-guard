# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The snapshot as plain text: the CLI status, NEXT.txt and the lock body."""

from __future__ import annotations

from typing import TYPE_CHECKING, Final

from book_guard._constants import DAILY_PASS_PAGES
from book_guard._sessions import NEEDS_CHECK, NEEDS_QUIZ, TOO_FAST
from book_guard._state import CREDITED

if TYPE_CHECKING:
    from book_guard._state import SessionView, Snapshot


_STATUS_TEXT: Final = {
    NEEDS_CHECK: "photograph page {check}",
    NEEDS_QUIZ: "write the summary at the PC (book-guard quiz)",
    TOO_FAST: "not counted: under 50 s per page",
    CREDITED: "credited",
}


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
            f"(pace line today: {p.required}; carried debt {p.carried_debt}; "
            f"{f'carried credit {p.carried_credit}; ' if p.carried_credit else ''}"
            f"books finished {p.finished_books})"
        ),
        (
            f"Today: {p.pages_today}/{DAILY_PASS_PAGES} pages "
            f"({'passed' if p.passed_today else 'not yet'}: "
            f"{DAILY_PASS_PAGES} pages a day open the lock even when behind)"
        ),
    ]
    if p.behind:
        lines.append(
            f"Debt: {p.behind} pages = {p.debt_per_day}/day over the "
            f"{p.days_left} counted days left this month"
            if p.days_left
            else f"Debt: {p.behind} pages, carried into next month"
        )
    lines.append(f"Escapes left this month: {snap.escapes_left}")
    todo = todo_lines(snap)
    if todo:
        lines += ["", "Next:", *(f"  * {t}" for t in todo)]
    if snap.sessions:
        lines += ["", "Recent sessions:"]
        lines += [f"  {session_line(v)}" for v in snap.sessions[-recent:]]
    return lines
