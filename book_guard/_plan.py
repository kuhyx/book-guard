# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""One month's day-by-day plan: quotas, and where surplus pages go.

Pure and exact (``Fraction``): a surplus split three ways must not drift.

Reading more than the line asks is a reward, not a pre-payment of tomorrow:
the moment the pages read pass the plan, the surplus is *moved* -- the day it
was earned absorbs it (so the plan meets the pages exactly, and nothing is
counted twice) and it comes off later days instead, evenly across the
remaining workdays (``freedays.WORKDAYS``) until they are empty, then evenly
across the remaining Fri-Mon days. What no remaining day can absorb is
left over at month end (:mod:`book_guard._pace` carries it).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from fractions import Fraction
from typing import TYPE_CHECKING

import freedays

if TYPE_CHECKING:
    from collections.abc import Mapping
    from datetime import date


def is_workday(day: date) -> bool:
    """Tue-Thu: the light days."""
    return day.weekday() in freedays.WORKDAYS


@dataclass
class MonthPlan:
    """The plan as of some day; ``line_before`` is what the lock reads."""

    quotas: dict[date, Fraction]
    extra: dict[date, Fraction] = field(default_factory=dict)
    leftover: Fraction = Fraction(0)
    unspread: Fraction = Fraction(0)
    """Debt in a month with no counted day: owed, but on no day's line."""

    def line_before(self, day: date) -> Fraction:
        """Pages the plan expects by the start of ``day``."""
        planned = sum((q for d, q in self.quotas.items() if d < day), Fraction(0))
        moved = sum((x for d, x in self.extra.items() if d < day), Fraction(0))
        return planned + moved

    @property
    def target(self) -> Fraction:
        """The month's requirement after carried credit came off it."""
        quotas = sum(self.quotas.values(), Fraction(0))
        return quotas + sum(self.extra.values(), Fraction(0)) + self.unspread


def spread_cut(
    quotas: dict[date, Fraction], days: list[date], amount: Fraction
) -> Fraction:
    """Take up to ``amount`` off ``days``: workdays evenly first, then the rest.

    Even means water-filling: every day in the group loses the same amount
    until the smallest hits zero, then the others share what is left.
    Returns how much was taken (less than ``amount`` only if all are empty).
    """
    taken = Fraction(0)
    for light in (True, False):
        pool = [d for d in days if is_workday(d) == light and quotas[d] > 0]
        while taken < amount and pool:
            cut = min((amount - taken) / len(pool), *(quotas[d] for d in pool))
            for d in pool:
                quotas[d] -= cut
            taken += cut * len(pool)
            pool = [d for d in pool if quotas[d] > 0]
    return taken


@dataclass(frozen=True)
class MonthInput:
    """Everything one month's plan is derived from.

    Attributes:
        days: Every day of the month, in order.
        counted: The days the target spreads over (paced, not free).
        weights: Each counted day's share of the month's base.
        target: The base plus carried debt; the base split by weight, the
            debt evenly over the counted days.
        credit: Surplus carried in from earlier months, spent from day one.
        pages_on: Pages credited on each day (free days included).
    """

    days: list[date]
    counted: list[date]
    weights: Mapping[date, Fraction]
    target: int
    credit: Fraction
    pages_on: Mapping[date, int]


def _opening_plan(month: MonthInput) -> MonthPlan:
    """Day one: the target split by weight, the carried credit spent."""
    total = sum(month.weights[d] for d in month.counted)
    if not total:
        return MonthPlan({}, leftover=month.credit, unspread=Fraction(month.target))
    # The base quotas keep their Tue-Thu/Fri-Mon weights; carried debt is
    # split evenly, one equal share per counted day, like an in-month debt.
    debt = Fraction(month.target - total, len(month.counted))
    quotas = {d: month.weights[d] + debt for d in month.counted}
    taken = spread_cut(quotas, month.counted, month.credit)
    return MonthPlan(quotas, leftover=month.credit - taken)


def plan_month(month: MonthInput, until: date) -> MonthPlan:
    """Walk ``month`` through ``until`` (inclusive), moving every surplus.

    ``until`` is the last day whose reading is known: today, or month end.
    """
    plan = _opening_plan(month)
    read = planned = Fraction(0)
    for day in month.days:
        if day > until:
            break
        read += month.pages_on.get(day, 0)
        planned += plan.quotas.get(day, Fraction(0))
        if read <= planned:
            continue
        later = [d for d in month.counted if d > day]
        moved = spread_cut(plan.quotas, later, read - planned)
        if moved:
            plan.extra[day] = moved
            planned += moved
    plan.leftover += max(read - planned, Fraction(0))
    return plan
