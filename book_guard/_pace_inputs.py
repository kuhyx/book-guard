# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What the app's port of the plan runs on, and a day's numbers as JSON.

``state.json``'s ``pace_inputs`` carries the credits per day, the free days,
the sick days and the plan's constants, so the app computes any day's view offline
(``app/lib/src/pace_*.dart``). ``scripts/pace_goldens.py`` writes
:func:`view_json` for many scenarios; the Dart port must match every number.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import TYPE_CHECKING, Any, Final

import freedays

from book_guard._constants import (
    EDGE_WEIGHT,
    MIDWEEK_WEIGHT,
    MONTHLY_GOAL_START,
    MONTHLY_PAGES,
    OFFDAY_PAGES,
    PACE_START_DATE,
    QUOTA_SWITCH_DATE,
    RESPLIT_DATE,
    WEEKEND_CAP_PAGES,
    WEEKEND_WEIGHT,
    WORKDAY_PAGES,
)
from book_guard._ledger import CREDIT
from book_guard._pace import month_start
from book_guard._pace_view import cached
from book_guard._quotas import is_weekend, weight

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard._ledger import Ledger
    from book_guard._pace_view import DayView

_A_WEEK: Final = [
    QUOTA_SWITCH_DATE + timedelta(days=i - QUOTA_SWITCH_DATE.weekday())
    for i in range(7)
]
"""Mon..Sun of one week, to read the weekday classes off :mod:`book_guard._quotas`."""


def credits_by_day(ledger: Ledger) -> dict[str, int]:
    """Pages credited per day since the first paced month, for the app's port."""
    first = month_start(PACE_START_DATE).isoformat()
    out: dict[str, int] = {}
    for credit in ledger.of_kind(CREDIT):
        if credit.day >= first:
            out[credit.day] = out.get(credit.day, 0) + credit.amount
    return dict(sorted(out.items()))


def rules() -> dict[str, Any]:
    """The constants the app's port of :mod:`book_guard._plan` runs on.

    Weekdays are Python's (Mon 0 .. Sun 6).
    """
    return {
        "pace_start": PACE_START_DATE.isoformat(),
        "monthly_goal_start": MONTHLY_GOAL_START.isoformat(),
        "monthly_pages": MONTHLY_PAGES,
        "quota_switch": QUOTA_SWITCH_DATE.isoformat(),
        "resplit": RESPLIT_DATE.isoformat(),
        "workday_pages": WORKDAY_PAGES,
        "offday_pages": OFFDAY_PAGES,
        "workdays": sorted(freedays.WORKDAYS),
        "midweek_days": [
            i for i, d in enumerate(_A_WEEK) if weight(d) == MIDWEEK_WEIGHT
        ],
        "weekend_days": [i for i, d in enumerate(_A_WEEK) if is_weekend(d)],
        "midweek_weight": MIDWEEK_WEIGHT,
        "edge_weight": EDGE_WEIGHT,
        "weekend_weight": WEEKEND_WEIGHT,
        "weekend_cap": WEEKEND_CAP_PAGES,
    }


def pace_inputs(
    ledger: Ledger,
    today: date,
    is_free: Callable[[date], bool],
    sick: frozenset[date],
) -> dict[str, Any]:
    """Everything the app needs to compute any day offline (state.json).

    Free days run from the first paced month to the end of next year, so a
    picked day or a simulation in that range is exact. Sick days are the
    whole pool, in the same range.
    """
    first = month_start(PACE_START_DATE)
    last = date(today.year + 1, 12, 31)
    check = cached(is_free)
    return {
        "today": today.isoformat(),
        "rules": rules(),
        "credits": credits_by_day(ledger),
        "free_days": [d.isoformat() for d in _span(first, last) if check(d)],
        "sick_days": sorted(d.isoformat() for d in sick if first <= d <= last),
    }


def view_json(view: DayView) -> dict[str, Any]:
    """A day's numbers, as the goldens and the app compare them."""
    p = view.pace
    return {
        "day": view.day.isoformat(),
        "kind": view.kind,
        "required": view.required,
        "credited": view.credited,
        "assumed": view.assumed,
        "line": p.required,
        "target": p.target,
        "month_pages": p.pages,
        "behind": p.behind,
        "carried_debt": p.carried_debt,
        "carried_credit": p.carried_credit,
        "free": view.free,
        "sick": view.sick,
        "old_rule": view.old_rule,
    }


def _span(first: date, last: date) -> list[date]:
    return [first + timedelta(days=i) for i in range((last - first).days + 1)]
