# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What today asks beyond the line: its requirement, and where the debt goes.

Pure, from a month's plan (:mod:`book_guard._plan`). From
:data:`RESPLIT_DATE` the morning's split already holds the debt, so no day
takes a share on top; only what the split could not place is left. From
:data:`QUOTA_SWITCH_DATE` to it the debt went onto the month's remaining
weekend days, none past :data:`WEEKEND_CAP_PAGES`; before it, evenly over
every remaining counted day.
"""

from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
import math
from typing import TYPE_CHECKING

from book_guard._constants import QUOTA_SWITCH_DATE
from book_guard._ledger import CREDIT
from book_guard._plan import day_requirement, weekend_days
from book_guard._quotas import fill_weekends

if TYPE_CHECKING:
    from datetime import date

    from book_guard._ledger import Ledger
    from book_guard._plan import MonthInput, MonthPlan


@dataclass(frozen=True)
class Ask:
    """Today's requirement and the debt's spread."""

    required: int = 0
    """Today's quota after the moves plus, on a weekend, its debt share,
    rounded up -- fixed at the start of the day. The day's credited pages
    reaching it earn the bonus from :data:`QUOTA_SWITCH_DATE` (see
    :attr:`bonus_at`). 0 on a free or sick day."""
    bonus: bool = False
    """A credit row dated today already carries the bonus."""
    debt_per_day: int = 0
    """Extra pages a day on :attr:`debt_days` that clear the debt (from the
    switch: per remaining weekend day, none past 60)."""
    debt_days: int = 0
    """The days the debt is spread over: the remaining Sat/Sun counted days
    (before the switch: every remaining counted day), today included."""
    debt_unplaced: int = 0
    """Debt no remaining day can hold: it carries into the next month."""
    bonus_at: int = 0
    """Credited pages today that earn the +1h: :attr:`required`, except on a
    sick day, which asks nothing yet earns at the requirement it would have
    had without being sick."""
    daily: bool = False
    """From the plan's resplit: one number a day -- :attr:`required` alone is
    what today asks, and reading it opens the lock and earns the hour."""
    excused: int = 0
    """Pages the month's sick days were excused so far (off the target),
    rounded up."""


def _spread(
    plan: MonthPlan, month: MonthInput, today: date, behind: int
) -> tuple[int, int, int]:
    """``behind`` spread on: pages a day, over how many days, what fits nowhere."""
    if plan.resplit is not None and today >= plan.resplit:
        # The morning's split holds every debt it can; no day takes more.
        return 0, 0, math.ceil(plan.unspread)
    if today < QUOTA_SWITCH_DATE:
        days = sum(1 for d in month.counted if d >= today and d not in month.sick)
        return (math.ceil(behind / days), days, 0) if days else (0, 0, behind)
    weekends = weekend_days(month, today)
    shares, rest = fill_weekends(plan.quotas, weekends, Fraction(behind))
    per_day = max(shares.values(), default=Fraction(0))
    return math.ceil(per_day), len(weekends), math.ceil(rest)


def today_ask(
    ledger: Ledger, plan: MonthPlan, month: MonthInput, today: date, behind: int
) -> Ask:
    """What ``today`` asks, given the month's plan and the pages ``behind`` now.

    The bonus threshold is the requirement; on a sick day
    :func:`book_guard._pace.compute_pace` replaces it.
    """
    per_day, days, unplaced = _spread(plan, month, today, behind)
    required = math.ceil(day_requirement(plan, month, today))
    return Ask(
        daily=plan.resplit is not None and today >= plan.resplit,
        excused=math.ceil(sum(plan.excused.values(), Fraction(0))),
        required=required,
        bonus_at=required,
        bonus=any(
            e.day == today.isoformat() and e.detail.get("bonus") == "1"
            for e in ledger.of_kind(CREDIT)
        ),
        debt_per_day=per_day,
        debt_days=days,
        debt_unplaced=unplaced,
    )
