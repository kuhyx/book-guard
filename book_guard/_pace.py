# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The pace line and the year-wide carry. Pure: ledger in, numbers out.

Nothing here is stored. Every run re-derives, from the credits alone:

* **base** for a month = :data:`MONTHLY_PAGES` (before
  :data:`MONTHLY_GOAL_START`: the sum of its counted days' quotas), split
  over its counted days -- before :data:`QUOTA_SWITCH_DATE` 20:40
  Tue-Thu:Fri-Mon, from it 15:30:50 Tue-Thu:Mon,Fri:Sat,Sun with weekends
  capped at 60 (:mod:`book_guard._quotas`);
* **balance** = every past month's base minus the pages read in it: what is
  owed (or, negative, read ahead) beyond the bases;
* **carry** into a month = the balance split evenly over the months left in
  the year, this one included, rounded away from zero -- so the earliest
  months take the odd pages and none is lost. January takes all of
  December's balance (no month of its year is left to share it);
* **target** = base + carry, never below 0. From the switch the whole target
  is split by weight; before it, a carried debt was spread evenly over the
  counted days and a carried surplus came off them like an in-month surplus
  (see :mod:`book_guard._plan`);
* **required by today** = the plan's line at the *start* of today -- today's
  share is due tomorrow, so an evening reader is never locked in the morning
  for pages they meant to read tonight, and a declared free day moves the
  line instead of silently creating a deficit. Pages read past the line come
  off later Mon-Fri days (before the switch: Tue-Thu, then Fri-Mon).
* **debt share** = the pages behind the line spread evenly over the month's
  remaining Sat/Sun days, today included, none past 60 -- recomputed every
  day; what fits nowhere, or is still short at month end, goes into the
  balance. (Before the switch: evenly over all remaining counted days.)
* **today's requirement** = today's quota after the moves plus, on a
  weekend, today's debt share, fixed at the start of the day and rounded up.
  Reaching it earns the day's bonus (:mod:`book_guard._bonus`).
* **sick day** (``sickdays``) = asks nothing and its share is dropped, not
  re-split: the month's target falls by exactly that day's quota and every
  other day asks what it would have (:mod:`book_guard._plan`). The share
  stays out of the year balance too. Reading on it still earns the bonus at
  the requirement the day would have had (:attr:`Ask.bonus_at`).
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from datetime import date, timedelta
from fractions import Fraction
import math
from typing import TYPE_CHECKING

from book_guard._ask import Ask, today_ask
from book_guard._books import all_books
from book_guard._constants import (
    DAILY_PASS_PAGES,
    MONTHLY_GOAL_START,
    MONTHLY_PAGES,
    OFFDAY_PAGES,
    PACE_START_DATE,
    QUOTA_SWITCH_DATE,
    WORKDAY_PAGES,
)
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
    """This month's share of the balance owed from earlier months."""
    pages: int
    required: int
    finished_books: int
    carried_credit: int = 0
    """This month's share of the pages read ahead in earlier months."""
    pages_today: int = 0
    days_left: int = 0
    """Counted (non-free, non-sick) days left in the month, today included."""
    ask: Ask = field(default_factory=Ask)
    """Today's requirement (the bonus threshold) and the debt's spread."""

    @property
    def behind(self) -> int:
        """Pages short of the line right now (0 when on pace)."""
        return max(0, self.required - self.pages)

    @property
    def passed_today(self) -> bool:
        """Today's credited pages reach :data:`DAILY_PASS_PAGES`."""
        return self.pages_today >= DAILY_PASS_PAGES


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


def _months_left(first: date) -> int:
    """Months the balance is spread over, ``first``'s included.

    January's is 1: December's balance has no month of its year left to share
    it, so all of it lands on the new year's first month.
    """
    return 1 if first.month == 1 else 13 - first.month


def _share(balance: int, months: int) -> int:
    """``balance / months``, rounded away from zero: the odd pages go first."""
    share = -(-abs(balance) // months)
    return share if balance >= 0 else -share


@dataclass(frozen=True)
class _Calendar:
    """Which days are free (out of the split) and sick (in it, asking nothing)."""

    is_free: Callable[[date], bool]
    sick: frozenset[date]


def _plan(
    ledger: Ledger, first: date, cal: _Calendar, carry: int, until: date
) -> tuple[MonthPlan, MonthInput, int, int]:
    """The month's plan through ``until``: plan, its input, books, base."""
    counted = _counted(first, cal.is_free)
    quotas = {d: _quota(d) for d in counted}
    total = sum(quotas.values())
    base = MONTHLY_PAGES if first >= MONTHLY_GOAL_START else total
    weights = {d: Fraction(q * base, total) for d, q in quotas.items()}
    pages_on, finished = _month_totals(ledger, first)
    month = MonthInput(
        days=_days(first),
        counted=counted,
        weights=weights,
        target=base + max(carry, 0),
        credit=Fraction(max(-carry, 0)),
        pages_on=pages_on,
        sick=cal.sick,
    )
    switch = QUOTA_SWITCH_DATE if _next_month(first) > QUOTA_SWITCH_DATE else None
    return plan_month(month, until, switch), month, finished, base


def _balance(ledger: Ledger, cal: _Calendar, current: date) -> int:
    """Every month before ``current``: its base minus the pages read in it."""
    first = month_start(PACE_START_DATE)
    balance = 0
    while first < current:
        month_end = _next_month(first) - timedelta(days=1)
        done, month, _, base = _plan(ledger, first, cal, 0, month_end)
        # A sick day's share is owed by nobody, so it never reaches the
        # balance either (rounded so the remainder is still owed).
        owed = math.ceil(base - sum(done.excused.values(), Fraction(0)))
        balance += owed - sum(month.pages_on.values())
        first = _next_month(first)
    return balance


def compute_pace(
    ledger: Ledger,
    today: date,
    is_free: Callable[[date], bool],
    *,
    sick: frozenset[date],
) -> Pace:
    """The pace position for ``today``'s month; ``sick``: the sick days."""
    cal = _Calendar(is_free, sick)
    current = month_start(today)
    carry = _share(_balance(ledger, cal, current), _months_left(current))
    plan, month, finished, _ = _plan(ledger, current, cal, carry, today)
    pages = sum(month.pages_on.values())
    required = math.ceil(plan.line_before(today))
    ask = today_ask(ledger, plan, month, today, max(0, required - pages))
    if today in sick:
        # The bonus is earned at the requirement the day would have had:
        # being sick changes what is owed, not what earns the hour.
        well = compute_pace(ledger, today, is_free, sick=sick - {today})
        ask = replace(ask, bonus_at=well.ask.required)
    return Pace(
        month=current,
        target=math.ceil(plan.target),
        carried_debt=max(carry, 0),
        pages=pages,
        required=required,
        finished_books=finished,
        carried_credit=max(-carry, 0),
        pages_today=month.pages_on.get(today, 0),
        days_left=sum(1 for d in month.counted if d >= today and d not in sick),
        ask=ask,
    )
