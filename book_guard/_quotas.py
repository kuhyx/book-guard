# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The weekday plan from :data:`QUOTA_SWITCH_DATE`: weights, cap, moves.

Pure and exact (``Fraction``):

* a counted day weighs 15 (Tue-Thu), 30 (Mon, Fri) or 50 (Sat, Sun), and a
  target is split over counted days by those weights -- unless that would
  ask more than :data:`WEEKEND_CAP_PAGES` of a weekend day: then the
  weekends sit at the cap and Mon-Fri share the rest, still 15:30;
* a surplus comes off the remaining Mon-Fri days, evenly (water-filling down
  to 0), never off a weekend;
* a debt goes onto the remaining weekend days, evenly, and never takes a
  weekend day past the cap; what does not fit is returned as unplaced.

The weekday classes are local on purpose: ``freedays`` (kuhyx/utils) owns
the free-day pool, not this guard's weights.
"""

from __future__ import annotations

from fractions import Fraction
from typing import TYPE_CHECKING, Final

from book_guard._constants import (
    EDGE_WEIGHT,
    MIDWEEK_WEIGHT,
    WEEKEND_CAP_PAGES,
    WEEKEND_WEIGHT,
)

if TYPE_CHECKING:
    from datetime import date

_MIDWEEK: Final = frozenset({1, 2, 3})
"""Tue, Wed, Thu (``date.weekday()``)."""
_WEEKEND: Final = frozenset({5, 6})
"""Sat, Sun."""


def is_weekend(day: date) -> bool:
    """Sat or Sun: the days that carry debt and never lose surplus."""
    return day.weekday() in _WEEKEND


def weight(day: date) -> int:
    """A counted day's weight: Tue-Thu 15, Mon/Fri 30, Sat/Sun 50."""
    if is_weekend(day):
        return WEEKEND_WEIGHT
    return MIDWEEK_WEIGHT if day.weekday() in _MIDWEEK else EDGE_WEIGHT


def split(total: Fraction, days: list[date]) -> tuple[dict[date, Fraction], Fraction]:
    """``total`` over ``days`` by weight, weekends capped; and what found no day.

    The second value is non-zero only when no day can take it: no day at
    all, or capped weekends with no Mon-Fri day to take the rest.
    """
    units = sum(weight(d) for d in days)
    if not units:
        return {}, total
    scale = total / units
    weekends = [d for d in days if is_weekend(d)]
    if scale * WEEKEND_WEIGHT <= WEEKEND_CAP_PAGES:
        return {d: weight(d) * scale for d in days}, Fraction(0)
    quotas = {d: Fraction(WEEKEND_CAP_PAGES) for d in weekends}
    rest = total - WEEKEND_CAP_PAGES * len(weekends)
    weekdays = [d for d in days if not is_weekend(d)]
    week_units = sum(weight(d) for d in weekdays)
    if not week_units:
        return quotas, rest
    quotas.update({d: weight(d) * rest / week_units for d in weekdays})
    return quotas, Fraction(0)


def drain(quotas: dict[date, Fraction], pool: list[date], amount: Fraction) -> Fraction:
    """Take up to ``amount`` off ``pool`` evenly; return how much was taken.

    Even means water-filling: every day loses the same amount until the
    smallest hits zero, then the others share what is left.
    """
    taken = Fraction(0)
    pool = [d for d in pool if quotas[d] > 0]
    while taken < amount and pool:
        cut = min((amount - taken) / len(pool), *(quotas[d] for d in pool))
        for d in pool:
            quotas[d] -= cut
        taken += cut * len(pool)
        pool = [d for d in pool if quotas[d] > 0]
    return taken


def cut_weekdays(
    quotas: dict[date, Fraction], days: list[date], amount: Fraction
) -> Fraction:
    """Take up to ``amount`` off the Mon-Fri ``days``, evenly; weekends keep theirs."""
    return drain(quotas, [d for d in days if not is_weekend(d)], amount)


def fill_weekends(
    quotas: dict[date, Fraction], days: list[date], debt: Fraction
) -> tuple[dict[date, Fraction], Fraction]:
    """``debt`` over the weekend ``days`` evenly, each up to the cap.

    Returns each weekend day's share and the part no weekend can hold.
    ``quotas`` is not changed: debt is what the days ask, not the line.
    """
    room = {
        d: max(WEEKEND_CAP_PAGES - quotas.get(d, Fraction(0)), Fraction(0))
        for d in days
        if is_weekend(d)
    }
    left = dict(room)
    placed = drain(left, list(room), debt)
    return {d: room[d] - left[d] for d in room}, debt - placed
