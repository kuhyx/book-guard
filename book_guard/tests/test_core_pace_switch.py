# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The 2026-10-12 switch: no jump, 15:30:50 months, the 60 cap, moves."""

from __future__ import annotations

from datetime import date, timedelta
from fractions import Fraction
import math

from book_guard import _pace, _plan
from book_guard._constants import QUOTA_SWITCH_DATE
from book_guard._ledger import Ledger
from book_guard.tests.test_core_pace import _credit, _never

OCT = date(2026, 10, 1)
NOV = date(2026, 11, 1)
READ = Ledger(
    [
        _credit(day, pages)
        for day, pages in (
            ("2026-10-02", 44),
            ("2026-10-03", 53),
            ("2026-10-04", 47),
            ("2026-10-07", 69),
            ("2026-10-08", 17),
            ("2026-10-09", 14),
            ("2026-10-10", 52),
            ("2026-10-11", 36),
        )
    ]
)
"""Shaped like the real October: ahead some days, behind on others."""
OCT_DONE = _credit("2026-10-31", 1000)
"""October read in full: November starts with no carry."""


def _plans(ledger: Ledger, until: date) -> tuple[_plan.MonthPlan, _plan.MonthPlan]:
    """October's plan with and without the switch."""
    new, month, _, _ = _pace._plan(
        ledger, OCT, _pace._Calendar(_never, frozenset()), 0, until
    )
    return _plan.plan_month(month, until), new


def test_the_line_does_not_jump_at_the_switch() -> None:
    old, new = _plans(READ, QUOTA_SWITCH_DATE)
    assert new.line_before(QUOTA_SWITCH_DATE) == old.line_before(QUOTA_SWITCH_DATE)
    for day in (OCT + timedelta(days=i) for i in range(11)):
        assert new.line_before(day) == old.line_before(day)
        assert new.quotas.get(day) == old.quotas.get(day)
    assert new.target == old.target == 1000
    pace = _pace.compute_pace(READ, QUOTA_SWITCH_DATE, _never, sick=frozenset())
    assert pace.required == math.ceil(old.line_before(QUOTA_SWITCH_DATE))


def test_the_rest_of_october_is_re_split_15_30_50() -> None:
    old, new = _plans(Ledger(), QUOTA_SWITCH_DATE)
    rest = 1000 - old.line_before(QUOTA_SWITCH_DATE)
    # Oct 12-31: 6 Mon/Fri, 9 Tue-Thu, 5 Sat/Sun = 565 units, under the cap.
    unit = rest / 565
    assert new.quotas[date(2026, 10, 12)] == 30 * unit
    assert new.quotas[date(2026, 10, 13)] == 15 * unit
    assert new.quotas[date(2026, 10, 17)] == 50 * unit
    assert sum(q for d, q in new.quotas.items() if d >= QUOTA_SWITCH_DATE) == rest


def test_november_rescales_the_thousand() -> None:
    plan, _, _, _ = _pace._plan(
        Ledger(), NOV, _pace._Calendar(_never, frozenset()), 0, NOV
    )
    # 9 weekend, 9 Mon/Fri, 12 Tue-Thu days: 900 units.
    assert plan.quotas[NOV] == Fraction(500, 9)
    assert plan.quotas[date(2026, 11, 2)] == Fraction(100, 3)
    assert plan.quotas[date(2026, 11, 3)] == Fraction(50, 3)
    assert plan.target == 1000


def test_february_hits_the_weekend_cap() -> None:
    feb = date(2027, 2, 1)
    plan, _, _, _ = _pace._plan(
        Ledger(), feb, _pace._Calendar(_never, frozenset()), 0, feb
    )
    # 820 units would ask 60.98 a weekend day: 60, and Mon-Fri share 520.
    assert plan.quotas[date(2027, 2, 6)] == 60
    assert plan.quotas[feb] == Fraction(30 * 520, 420)
    assert plan.quotas[date(2027, 2, 2)] == Fraction(15 * 520, 420)
    assert plan.target == 1000


def test_carried_debt_is_inside_the_rescale() -> None:
    ledger = Ledger([_credit("2026-10-05", 100)])
    # November carries 450: 1450 caps the weekends at 60 and Mon-Fri share
    # the other 910 (450 units): Mon/Fri 60.67, Tue-Thu 30.33.
    monday = _pace.compute_pace(ledger, date(2026, 11, 2), _never, sick=frozenset())
    assert (monday.target, monday.required) == (1450, 60)
    assert monday.ask.required == math.ceil(Fraction(30 * 910, 450))
    wednesday = _pace.compute_pace(ledger, date(2026, 11, 4), _never, sick=frozenset())
    assert wednesday.required == math.ceil(60 + Fraction(45 * 910, 450))


def test_surplus_comes_off_mon_fri_only() -> None:
    ledger = Ledger([OCT_DONE, _credit("2026-11-01", 100)])
    plan, _, _, _ = _pace._plan(
        ledger, NOV, _pace._Calendar(_never, frozenset()), 0, NOV
    )
    cut = (100 - Fraction(500, 9)) / 21
    assert plan.quotas[date(2026, 11, 2)] == Fraction(100, 3) - cut
    assert plan.quotas[date(2026, 11, 4)] == Fraction(50, 3) - cut
    assert plan.quotas[date(2026, 11, 7)] == Fraction(500, 9)
    tuesday = _pace.compute_pace(ledger, date(2026, 11, 3), _never, sick=frozenset())
    assert tuesday.ask.required == math.ceil(Fraction(50, 3) - cut)


def test_debt_goes_to_weekends_only() -> None:
    # Nothing read: Tuesday asks its quota alone, the debt waits for Saturday.
    tuesday = _pace.compute_pace(
        Ledger([OCT_DONE]), date(2026, 11, 3), _never, sick=frozenset()
    )
    assert tuesday.behind > 0
    assert tuesday.ask.required == math.ceil(Fraction(50, 3))
    # Sat Nov 7: 172.2 behind; 8 weekend days left, each with room 4.44.
    saturday = _pace.compute_pace(
        Ledger([OCT_DONE]), date(2026, 11, 7), _never, sick=frozenset()
    )
    assert saturday.ask.required == 60
    assert (saturday.ask.debt_per_day, saturday.ask.debt_days) == (5, 8)
    assert saturday.ask.debt_unplaced == math.ceil(173 - 8 * (60 - Fraction(500, 9)))


def test_debt_no_weekend_holds_carries_into_next_month() -> None:
    last = _pace.compute_pace(Ledger(), date(2026, 11, 30), _never, sick=frozenset())
    assert (last.ask.debt_per_day, last.ask.debt_days) == (0, 0)
    assert last.ask.debt_unplaced == last.behind > 0
    december = _pace.compute_pace(Ledger(), date(2026, 12, 1), _never, sick=frozenset())
    assert december.carried_debt == 2000


def test_a_free_day_asks_nothing() -> None:
    day = date(2026, 11, 7)
    pace = _pace.compute_pace(Ledger(), day, lambda d: d == day, sick=frozenset())
    assert pace.ask.required == 0
    assert pace.ask.debt_days == 7


def test_before_the_switch_the_debt_is_spread_over_every_day() -> None:
    pace = _pace.compute_pace(Ledger(), date(2026, 10, 11), _never, sick=frozenset())
    assert pace.ask.debt_days == pace.days_left == 21
    assert pace.ask.debt_unplaced == 0
