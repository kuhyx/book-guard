# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_plan: water-filling a surplus across days."""

from __future__ import annotations

from datetime import date
from fractions import Fraction

from book_guard import _plan

TUE, WED, FRI, SAT = (
    date(2026, 10, 6),
    date(2026, 10, 7),
    date(2026, 10, 9),
    date(2026, 10, 10),
)


def test_cut_drains_workdays_evenly_then_the_rest() -> None:
    quotas = {TUE: Fraction(2), WED: Fraction(10), FRI: Fraction(40), SAT: Fraction(40)}
    taken = _plan.spread_cut(quotas, [TUE, WED, FRI, SAT], Fraction(16))
    # Tue empties at 2, Wed takes the other 2+2+... = 10, then 4 split Fri/Sat.
    assert taken == 16
    assert quotas == {TUE: 0, WED: 0, FRI: 38, SAT: 38}


def test_cut_stops_when_everything_is_empty() -> None:
    quotas = {TUE: Fraction(5), FRI: Fraction(5)}
    assert _plan.spread_cut(quotas, [TUE, FRI], Fraction(30)) == 10
    assert set(quotas.values()) == {0}


def test_no_counted_day_keeps_the_target_unspread() -> None:
    month = _plan.MonthInput(
        days=[TUE], counted=[], weights={}, target=50, credit=Fraction(3), pages_on={}
    )
    plan = _plan.plan_month(month, TUE)
    assert plan.target == Fraction(50)
    assert plan.leftover == Fraction(3)
    assert plan.line_before(WED) == Fraction(0)
