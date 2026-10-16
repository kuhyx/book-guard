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

From :data:`QUOTA_SWITCH_DATE` the rules are :mod:`book_guard._quotas`'
instead: the split is 15:30:50 with weekends capped, and a surplus comes off
the remaining Mon-Fri days only. The switch month walks the old rules up to
the switch, then re-splits what is left of its target over the days from the
switch on -- the line at the switch is the old line exactly.

A **sick day** (``sickdays``, one that does not keep ``book``) is not a free
day: it keeps its place and its weight in the split and in every surplus cut,
so every other day's quota is exactly what it would be without it -- but it
asks nothing. Its quota after
the moves is taken off the line and the target (:attr:`MonthPlan.excused`),
never re-split over the other days; pages read on it count like any others.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from fractions import Fraction
from typing import TYPE_CHECKING

import freedays

from book_guard._quotas import cut_weekdays, drain, fill_weekends, is_weekend, split

if TYPE_CHECKING:
    from collections.abc import Callable, Mapping
    from datetime import date

    Cut = Callable[[dict[date, Fraction], list[date], Fraction], Fraction]


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
    excused: dict[date, Fraction] = field(default_factory=dict)
    """Sick days' quotas after the moves: off the line, the target and
    :attr:`quotas`, owed by nobody."""

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

    The rule before :data:`QUOTA_SWITCH_DATE`. Even means water-filling
    (:func:`book_guard._quotas.drain`). Returns how much was taken (less than
    ``amount`` only if all are empty).
    """
    taken = Fraction(0)
    for light in (True, False):
        pool = [d for d in days if is_workday(d) == light]
        taken += drain(quotas, pool, amount - taken)
    return taken


@dataclass(frozen=True)
class MonthInput:
    """Everything one month's plan is derived from.

    Attributes:
        days: Every day of the month, in order.
        counted: The days the target spreads over (paced, not free; sick
            days included, so they keep their share of the split).
        weights: Each counted day's share of the month's base.
        target: The base plus carried debt; the base split by weight, the
            debt evenly over the counted days.
        credit: Surplus carried in from earlier months, spent from day one.
        pages_on: Pages credited on each day (free and sick days included).
        sick: Sick days: no quota of their own, see :attr:`MonthPlan.excused`.
    """

    days: list[date]
    counted: list[date]
    weights: Mapping[date, Fraction]
    target: int
    credit: Fraction
    pages_on: Mapping[date, int]
    sick: frozenset[date] = frozenset()


def _opening_plan(month: MonthInput) -> MonthPlan:
    """Day one under the old rules: the target by weight, the credit spent."""
    total = sum(month.weights[d] for d in month.counted)
    if not total:
        return MonthPlan({}, leftover=month.credit, unspread=Fraction(month.target))
    # The base quotas keep their Tue-Thu/Fri-Mon weights; carried debt is
    # split evenly, one equal share per counted day, like an in-month debt.
    debt = Fraction(month.target - total, len(month.counted))
    quotas = {d: month.weights[d] + debt for d in month.counted}
    taken = spread_cut(quotas, month.counted, month.credit)
    return MonthPlan(quotas, leftover=month.credit - taken)


def _weekday_opening(month: MonthInput) -> MonthPlan:
    """Day one under the new rules: the target net of credit, split 15:30:50."""
    net = Fraction(month.target) - month.credit
    quotas, unspread = split(max(net, Fraction(0)), month.counted)
    return MonthPlan(quotas, leftover=max(-net, Fraction(0)), unspread=unspread)


def _resplit(plan: MonthPlan, month: MonthInput, switch: date) -> None:
    """Re-split what the old plan still asks from ``switch`` on, by the new rules."""
    rest = [d for d in month.counted if d >= switch]
    quotas, unspread = split(sum((plan.quotas[d] for d in rest), Fraction(0)), rest)
    plan.quotas.update(quotas)
    plan.unspread += unspread


def _walk(
    plan: MonthPlan, month: MonthInput, days: list[date], cut: Cut, start: Fraction
) -> Fraction:
    """Walk ``days``, moving each surplus off later days; return read - planned.

    ``start`` is read - planned before the first of ``days``. A sick day
    plans nothing: not reading on it is no deficit, reading on it is surplus.
    """
    ahead = start
    for day in days:
        planned = Fraction(0) if day in month.sick else plan.quotas.get(day, 0)
        ahead += month.pages_on.get(day, 0) - planned
        if ahead <= 0:
            continue
        moved = cut(plan.quotas, [d for d in month.counted if d > day], ahead)
        if moved:
            plan.extra[day] = moved
            ahead -= moved
    return ahead


def plan_month(month: MonthInput, until: date, switch: date | None = None) -> MonthPlan:
    """Walk ``month`` through ``until`` (inclusive), moving every surplus.

    ``until`` is the last day whose reading is known: today, or month end.
    ``switch`` is the first day of the new rules (``None``: old rules only).
    """
    known = [d for d in month.days if d <= until]
    if switch is not None and switch <= month.days[0]:
        plan = _weekday_opening(month)
        ahead = _walk(plan, month, known, cut_weekdays, Fraction(0))
    else:
        plan = _opening_plan(month)
        old = [d for d in known if switch is None or d < switch]
        ahead = _walk(plan, month, old, spread_cut, Fraction(0))
        if switch is not None and switch in month.days:
            _resplit(plan, month, switch)
            new = [d for d in known if d >= switch]
            ahead = _walk(plan, month, new, cut_weekdays, ahead)
    plan.leftover += max(ahead, Fraction(0))
    plan.excused = {d: plan.quotas.pop(d) for d in month.sick if d in plan.quotas}
    return plan


def day_requirement(plan: MonthPlan, month: MonthInput, day: date) -> Fraction:
    """What ``day`` asks: its quota after the moves, plus its debt share.

    Fixed at the start of the day: the debt is the line minus the pages read
    before ``day``, spread over the month's remaining weekend days
    (:func:`book_guard._quotas.fill_weekends`), so only a weekend carries it.
    A day with no quota (free, sick, or before the quotas) asks nothing.
    """
    if day not in plan.quotas:
        return Fraction(0)
    quota = plan.quotas[day]
    if not is_weekend(day):
        return quota
    shares, _ = fill_weekends(
        plan.quotas, weekend_days(month, day), debt_at(plan, month, day)
    )
    return quota + shares[day]


def debt_at(plan: MonthPlan, month: MonthInput, day: date) -> Fraction:
    """Pages behind the line at the start of ``day`` (0 when on pace)."""
    read = sum((p for d, p in month.pages_on.items() if d < day), 0)
    return max(plan.line_before(day) - read, Fraction(0))


def weekend_days(month: MonthInput, day: date) -> list[date]:
    """The month's counted, non-sick weekend days from ``day`` on, ``day`` included."""
    return [
        d for d in month.counted if d >= day and is_weekend(d) and d not in month.sick
    ]
