# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The 20-page day and the debt spread over the days left."""

from __future__ import annotations

from datetime import date
from fractions import Fraction
import math

from book_guard import _pace
from book_guard._constants import DAILY_PASS_PAGES, MONTHLY_PAGES
from book_guard._ledger import CREDIT, Entry, Ledger
from book_guard.tests.test_core_pace import OCTOBER, _credit, _never

# Nov 2026 has 12 Tue-Thu and 18 Fri-Mon days: 30 counted days, 960 quota.
NOVEMBER_DAYS = 30
SCALE = Fraction(MONTHLY_PAGES, 12 * 20 + 18 * 40)


def test_pages_today_sum_every_credited_session() -> None:
    ledger = Ledger(
        [
            _credit("2026-10-11", 12),
            Entry(entry_id="second", kind=CREDIT, day="2026-10-11", amount=8),
            _credit("2026-10-10", 50),
        ]
    )
    pace = _pace.compute_pace(ledger, date(2026, 10, 11), _never)
    assert pace.pages_today == DAILY_PASS_PAGES
    assert pace.passed_today
    assert pace.behind > 0


def test_nineteen_pages_do_not_pass() -> None:
    ledger = Ledger([_credit("2026-10-11", DAILY_PASS_PAGES - 1)])
    pace = _pace.compute_pace(ledger, date(2026, 10, 11), _never)
    assert (pace.pages_today, pace.passed_today) == (19, False)


def test_debt_is_split_evenly_over_the_days_left() -> None:
    pace = _pace.compute_pace(Ledger(), date(2026, 10, 11), _never)
    # Oct 11-31, today included: 21 counted days.
    assert pace.days_left == 21
    assert pace.debt_per_day == math.ceil(pace.behind / 21)


def test_free_days_are_not_days_left() -> None:
    def weekend_free(day: date) -> bool:
        return day >= date(2026, 10, 30)

    pace = _pace.compute_pace(Ledger(), date(2026, 10, 28), weekend_free)
    assert pace.days_left == 2  # Wed 28, Thu 29
    last = _pace.compute_pace(Ledger(), date(2026, 10, 31), weekend_free)
    # No counted day left: the debt carries into November instead.
    assert (last.days_left, last.debt_per_day) == (0, 0)
    assert last.behind > 0


def test_on_pace_owes_nothing_a_day() -> None:
    ledger = Ledger([_credit("2026-10-04", 400)])
    pace = _pace.compute_pace(ledger, date(2026, 10, 5), _never)
    assert (pace.behind, pace.debt_per_day) == (0, 0)


def test_carried_debt_is_spread_evenly_not_by_weight() -> None:
    ledger = Ledger([_credit("2026-10-05", 100)])
    # November carries half of October's shortfall (December the rest).
    share = Fraction((OCTOBER - 100) // 2, NOVEMBER_DAYS)
    # The 1000 keeps the 40:20 weights; Nov 1 is a Sunday, Nov 3 a Tuesday,
    # and each counted day carries one equal share of the debt.
    monday = _pace.compute_pace(ledger, date(2026, 11, 2), _never)
    assert monday.required == math.ceil(40 * SCALE + share)
    wednesday = _pace.compute_pace(ledger, date(2026, 11, 4), _never)
    assert wednesday.required == math.ceil((40 + 40 + 20) * SCALE + 3 * share)
