# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What today asks beyond the line: its requirement, and where the debt goes.

Pure, from a month's plan (:mod:`book_guard._plan`). From
:data:`QUOTA_SWITCH_DATE` the debt goes onto the month's remaining weekend
days, none past :data:`WEEKEND_CAP_PAGES`; before it, evenly over every
remaining counted day.
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
    reaching it earn the bonus from :data:`QUOTA_SWITCH_DATE`. 0 on a free day."""
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


def _spread(
    plan: MonthPlan, month: MonthInput, today: date, behind: int
) -> tuple[int, int, int]:
    """``behind`` spread on: pages a day, over how many days, what fits nowhere."""
    if today < QUOTA_SWITCH_DATE:
        days = sum(1 for d in month.counted if d >= today)
        return (math.ceil(behind / days), days, 0) if days else (0, 0, behind)
    weekends = weekend_days(month, today)
    shares, rest = fill_weekends(plan.quotas, weekends, Fraction(behind))
    per_day = max(shares.values(), default=Fraction(0))
    return math.ceil(per_day), len(weekends), math.ceil(rest)


def today_ask(
    ledger: Ledger, plan: MonthPlan, month: MonthInput, today: date, behind: int
) -> Ask:
    """What ``today`` asks, given the month's plan and the pages ``behind`` now."""
    per_day, days, unplaced = _spread(plan, month, today, behind)
    return Ask(
        required=math.ceil(day_requirement(plan, month, today)),
        bonus=any(
            e.day == today.isoformat() and e.detail.get("bonus") == "1"
            for e in ledger.of_kind(CREDIT)
        ),
        debt_per_day=per_day,
        debt_days=days,
        debt_unplaced=unplaced,
    )
