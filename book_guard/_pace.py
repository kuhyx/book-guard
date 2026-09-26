# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The pace line and the month-to-month debt. Pure: ledger in, numbers out.

Nothing here is stored. Every run re-derives, from the credits alone:

* **target** for a month = :data:`MONTHLY_PAGES` + the debt carried into it;
* **debt** carried out of a month = 0 if a book was finished in it, else
  ``max(0, target - pages read)``;
* **required by today** = ``ceil(target * elapsed / counted)``, where
  ``counted`` is the month's non-free days and ``elapsed`` the non-free days
  *before* today -- today's share is due tomorrow, so an evening reader is
  never locked in the morning for pages they meant to read tonight, and a
  declared free day moves the line instead of silently creating a deficit.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
import math
from typing import TYPE_CHECKING

from book_guard._books import all_books
from book_guard._constants import GATE_START_DATE, MONTHLY_PAGES
from book_guard._ledger import CREDIT

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard._ledger import Ledger


@dataclass(frozen=True)
class Pace:
    """Where this month stands."""

    month: date
    target: int
    carried_debt: int
    pages: int
    required: int
    finished_books: int

    @property
    def behind(self) -> int:
        """Pages short of the line right now (0 when on pace)."""
        return max(0, self.required - self.pages)


def month_start(day: date) -> date:
    """The first of ``day``'s month."""
    return day.replace(day=1)


def _next_month(first: date) -> date:
    return (first + timedelta(days=32)).replace(day=1)


def _days(first: date) -> list[date]:
    end = _next_month(first)
    return [first + timedelta(days=i) for i in range((end - first).days)]


def _last_pages(ledger: Ledger) -> dict[str, int]:
    """Each ISBN's last countable page, newest registration winning."""
    return {b.isbn: b.pages for b in all_books(ledger) if b.pages}


def _month_totals(ledger: Ledger, first: date) -> tuple[int, int]:
    """Pages credited in the month, and books finished in it."""
    last_pages = _last_pages(ledger)
    prefix = first.isoformat()[:7]
    pages = finished = 0
    for credit in ledger.of_kind(CREDIT):
        if not credit.day.startswith(prefix):
            continue
        pages += credit.amount
        last = last_pages.get(credit.detail.get("isbn", ""))
        end = credit.detail.get("end_page", "")
        if last and end.isdigit() and int(end) >= last:
            finished += 1
    return pages, finished


def compute_pace(ledger: Ledger, today: date, is_free: Callable[[date], bool]) -> Pace:
    """The pace position for ``today``'s month."""
    current = month_start(today)
    first = month_start(GATE_START_DATE)
    debt = 0
    while first < current:
        target = MONTHLY_PAGES + debt
        pages, finished = _month_totals(ledger, first)
        debt = 0 if finished else max(0, target - pages)
        first = _next_month(first)

    target = MONTHLY_PAGES + debt
    pages, finished = _month_totals(ledger, current)
    counted = [d for d in _days(current) if d >= GATE_START_DATE and not is_free(d)]
    elapsed = sum(1 for d in counted if d < today)
    required = math.ceil(target * elapsed / len(counted)) if counted else 0
    return Pace(
        month=current,
        target=target,
        carried_debt=debt,
        pages=pages,
        required=required,
        finished_books=finished,
    )
