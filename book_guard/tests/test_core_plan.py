# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_plan: water-filling a surplus across days."""

from __future__ import annotations

from datetime import date, timedelta
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


MON = date(2026, 11, 2)
WEEK = [MON + timedelta(days=i) for i in range(7)]
SAT_N, SUN_N = WEEK[5], WEEK[6]


def _week(
    pages: dict[int, int], *, target: int = 205, credit: int = 0
) -> _plan.MonthInput:
    """Nov 2-8 under the new rules: weights 30 15 15 15 30 50 50 (205)."""
    return _plan.MonthInput(
        days=WEEK,
        counted=WEEK,
        weights={},
        target=target,
        credit=Fraction(credit),
        pages_on={WEEK[i]: p for i, p in pages.items()},
    )


def test_debt_lands_on_the_weekends_left_and_respreads() -> None:
    # Mon-Thu on the line, Fri 6 short: Sat and Sun each ask 3 more.
    month = _week({0: 30, 1: 15, 2: 15, 3: 15, 4: 24})
    plan = _plan.plan_month(month, SAT_N, switch=MON)
    assert _plan.debt_at(plan, month, SAT_N) == 6
    assert _plan.day_requirement(plan, month, SAT_N) == 53
    # A weekday never carries debt; Sat read only its 50: Sun takes all 6.
    assert _plan.day_requirement(plan, month, WEEK[4]) == 30
    month = _week({0: 30, 1: 15, 2: 15, 3: 15, 4: 24, 5: 50})
    plan = _plan.plan_month(month, SUN_N, switch=MON)
    assert _plan.day_requirement(plan, month, SUN_N) == 56


def test_debt_past_the_cap_asks_60_and_the_rest_waits() -> None:
    month = _week({0: 30})
    plan = _plan.plan_month(month, SAT_N, switch=MON)
    assert _plan.debt_at(plan, month, SAT_N) == 75
    assert _plan.day_requirement(plan, month, SAT_N) == 60


def test_surplus_after_the_switch_spares_the_weekend() -> None:
    month = _week({0: 60})
    plan = _plan.plan_month(month, SAT_N, switch=MON)
    # 30 ahead on Monday: Tue-Fri lose 7.5 each, Sat/Sun keep 50.
    assert plan.extra == {MON: 30}
    assert [plan.quotas[d] for d in WEEK] == [30, 7.5, 7.5, 7.5, 22.5, 50, 50]
    assert _plan.day_requirement(plan, month, WEEK[1]) == Fraction(15, 2)


def test_surplus_mon_fri_cannot_hold_is_left_over() -> None:
    # Mon-Fri hold 75 of the 170 ahead; the weekends keep their 50 (the
    # reader is simply ahead of their line), the 95 is left over by Friday.
    plan = _plan.plan_month(_week({0: 200}), WEEK[4], switch=MON)
    assert plan.leftover == 200 - 30 - 75
    assert (plan.quotas[SAT_N], plan.target) == (Fraction(50), Fraction(205))


def test_new_rules_net_carried_credit_from_the_target() -> None:
    plan = _plan.plan_month(_week({}, target=205, credit=300), SUN_N, switch=MON)
    assert (plan.target, plan.leftover) == (Fraction(0), Fraction(95))


def test_a_day_with_no_quota_asks_nothing() -> None:
    plan = _plan.plan_month(_week({}), SUN_N, switch=MON)
    assert _plan.day_requirement(plan, _week({}), date(2026, 11, 9)) == 0


def test_a_switch_after_the_month_keeps_the_old_rules() -> None:
    month = _plan.MonthInput(
        days=[TUE, WED],
        counted=[TUE, WED],
        weights={TUE: Fraction(20), WED: Fraction(20)},
        target=40,
        credit=Fraction(0),
        pages_on={TUE: 30},
    )
    plan = _plan.plan_month(month, WED, switch=SAT)
    assert plan.quotas == {TUE: 20, WED: 10}
    assert plan.extra == {TUE: 10}
