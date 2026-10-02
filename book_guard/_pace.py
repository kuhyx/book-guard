# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The pace line and the month-to-month debt. Pure: ledger in, numbers out.

Nothing here is stored. Every run re-derives, from the credits alone:

* **target** for a month = the sum of its counted days' quotas
  (:data:`WORKDAY_PAGES` Tue-Thu, :data:`OFFDAY_PAGES` Fri-Mon) + the debt
  carried into it - the surplus credit carried into it;
* **debt** carried out of a month = 0 if a book was finished in it, else
  ``max(0, target - pages read)``; **credit** carried out = the surplus no
  day of the month could absorb (see :mod:`book_guard._plan`);
* **required by today** = the plan's line at the *start* of today -- today's
  share is due tomorrow, so an evening reader is never locked in the morning
  for pages they meant to read tonight, and a declared free day moves the
  line instead of silently creating a deficit. Pages read past the line come
  off later workdays first, then later Fri-Mon days (:mod:`book_guard._plan`).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from fractions import Fraction
import math
from typing import TYPE_CHECKING

from book_guard._books import all_books
from book_guard._constants import OFFDAY_PAGES, PACE_START_DATE, WORKDAY_PAGES
from book_guard._ledger import CREDIT
from book_guard._plan import MonthInput, MonthPlan, is_workday, plan_month

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
    carried_credit: int = 0

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


def _month_totals(ledger: Ledger, first: date) -> tuple[dict[date, int], int]:
    """Pages credited on each day of the month, and books finished in it."""
    last_pages = _last_pages(ledger)
    prefix = first.isoformat()[:7]
    pages: dict[date, int] = {}
    finished = 0
    for credit in ledger.of_kind(CREDIT):
        if not credit.day.startswith(prefix):
            continue
        day = date.fromisoformat(credit.day)
        pages[day] = pages.get(day, 0) + credit.amount
        last = last_pages.get(credit.detail.get("isbn", ""))
        end = credit.detail.get("end_page", "")
        if last and end.isdigit() and int(end) >= last:
            finished += 1
    return pages, finished


def _counted(first: date, is_free: Callable[[date], bool]) -> list[date]:
    """The month's days the pace line spreads over: paced and not free."""
    return [d for d in _days(first) if d >= PACE_START_DATE and not is_free(d)]


def _quota(day: date) -> int:
    """A counted day's page quota."""
    return WORKDAY_PAGES if is_workday(day) else OFFDAY_PAGES


def _plan(
    ledger: Ledger,
    first: date,
    is_free: Callable[[date], bool],
    carried: tuple[int, Fraction],
    until: date,
) -> tuple[MonthPlan, dict[date, int], int]:
    """The month's plan through ``until``, its daily pages, books finished."""
    debt, credit = carried
    counted = _counted(first, is_free)
    weights = {d: _quota(d) for d in counted}
    pages_on, finished = _month_totals(ledger, first)
    month = MonthInput(
        days=_days(first),
        counted=counted,
        weights=weights,
        target=sum(weights.values()) + debt,
        credit=credit,
        pages_on=pages_on,
    )
    plan = plan_month(month, until)
    return plan, pages_on, finished


def compute_pace(ledger: Ledger, today: date, is_free: Callable[[date], bool]) -> Pace:
    """The pace position for ``today``'s month."""
    current = month_start(today)
    first = month_start(PACE_START_DATE)
    debt, credit = 0, Fraction(0)
    while first < current:
        month_end = _next_month(first) - timedelta(days=1)
        plan, pages_on, finished = _plan(
            ledger, first, is_free, (debt, credit), month_end
        )
        short = plan.target - sum(pages_on.values())
        debt = 0 if finished else max(0, math.ceil(short))
        credit = plan.leftover
        first = _next_month(first)

    plan, pages_on, finished = _plan(ledger, current, is_free, (debt, credit), today)
    return Pace(
        month=current,
        target=math.ceil(plan.target),
        carried_debt=debt,
        pages=sum(pages_on.values()),
        required=math.ceil(plan.line_before(today)),
        finished_books=finished,
        carried_credit=math.floor(credit),
    )
