# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""From :data:`RESPLIT_DATE`: each morning splits what is left of the month.

What is left is the target net of carried credit, less the pages read
before that morning; it is split by weight over the counted days from that
morning on that are not sick (weekends capped,
:func:`book_guard._quotas.split`), and the morning's own share is the day's
one number. A sick day asks nothing and has no weight, so its share is owed
by the days left -- the month's target never shrinks for it -- and the share
a sick day before the resplit was excused under the old rules is owed again
from the resplit's morning. Each day then absorbs its own deviation
(:attr:`MonthPlan.extra`: read minus asked, a debt negative), so the line at
every morning is exactly the pages read and the next morning re-splits the
difference. The days after the last known one keep its split: the
projection that every day reads its number.
"""

from __future__ import annotations

from datetime import timedelta
from fractions import Fraction
from typing import TYPE_CHECKING

from book_guard._quotas import split

if TYPE_CHECKING:
    from datetime import date

    from book_guard._plan import MonthInput, MonthPlan


def _start_clean(plan: MonthPlan, month: MonthInput, start: date) -> int:
    """Drop the old plan from ``start`` on; return the pages read before it.

    Mid-month the old plan's line meets the pages at ``start``: the day
    before absorbs the difference, so nothing before ``start`` moves. What
    the old rules excused is owed again: :attr:`MonthPlan.excused` empties.
    """
    read = sum((p for d, p in month.pages_on.items() if d < start), 0)
    if start != month.days[0]:
        before = start - timedelta(days=1)
        moved = plan.extra.get(before, Fraction(0))
        plan.extra[before] = moved + read - plan.line_before(start)
    for day in [d for d in plan.quotas if d >= start]:
        del plan.quotas[day]
    plan.excused.clear()
    return read


def resplit_mornings(
    plan: MonthPlan, month: MonthInput, start: date, until: date
) -> None:
    """Every morning from ``start`` through ``until``, into ``plan``."""
    plan.resplit = start
    read = _start_clean(plan, month, start)
    net = Fraction(month.target) - month.credit
    quotas: dict[date, Fraction] = {}
    for day in [d for d in month.days if start <= d <= until]:
        left = net - read
        rest = [d for d in month.counted if d >= day and d not in month.sick]
        quotas, plan.unspread = split(max(left, Fraction(0)), rest)
        plan.leftover = max(-left, Fraction(0))
        ask = quotas.get(day, Fraction(0))
        if day in quotas:
            plan.quotas[day] = ask
        if day < until:
            plan.extra[day] = month.pages_on.get(day, 0) - ask
        read += month.pages_on.get(day, 0)
    plan.quotas.update({d: q for d, q in quotas.items() if d > until})
