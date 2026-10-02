# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The pace line and the month-to-month debt. Pure: ledger in, numbers out.

Nothing here is stored. Every run re-derives, from the credits alone:

* **target** for a month = the sum of its counted days' quotas
  (:data:`WORKDAY_PAGES` Tue-Thu, :data:`OFFDAY_PAGES` Fri-Mon) + the debt
  carried into it;
* **debt** carried out of a month = 0 if a book was finished in it, else
  ``max(0, target - pages read)``;
* **required by today** = ``ceil(target * elapsed / counted)``, where
  ``counted`` is the quota sum of the month's non-free days and ``elapsed``
  that of those *before* today -- today's share is due tomorrow, so an evening reader is
  never locked in the morning for pages they meant to read tonight, and a
  declared free day moves the line instead of silently creating a deficit.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
import math
from typing import TYPE_CHECKING

import freedays

from book_guard._books import all_books
from book_guard._constants import GATE_START_DATE, OFFDAY_PAGES, WORKDAY_PAGES
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


def _counted(first: date, is_free: Callable[[date], bool]) -> list[date]:
    """The month's days the pace line spreads over: gated and not free."""
    return [d for d in _days(first) if d >= GATE_START_DATE and not is_free(d)]


def _quota(day: date) -> int:
    """A counted day's page quota."""
    return WORKDAY_PAGES if day.weekday() in freedays.WORKDAYS else OFFDAY_PAGES


def compute_pace(ledger: Ledger, today: date, is_free: Callable[[date], bool]) -> Pace:
    """The pace position for ``today``'s month."""
    current = month_start(today)
    first = month_start(GATE_START_DATE)
    debt = 0
    while first < current:
        target = sum(map(_quota, _counted(first, is_free))) + debt
        pages, finished = _month_totals(ledger, first)
        debt = 0 if finished else max(0, target - pages)
        first = _next_month(first)

    counted = _counted(current, is_free)
    total = sum(map(_quota, counted))
    target = total + debt
    pages, finished = _month_totals(ledger, current)
    elapsed = sum(_quota(d) for d in counted if d < today)
    required = math.ceil(target * elapsed / total) if total else 0
    return Pace(
        month=current,
        target=target,
        carried_debt=debt,
        pages=pages,
        required=required,
        finished_books=finished,
    )
