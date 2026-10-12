# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_quotas: the 15:30:50 weights, the weekend cap, surplus and debt moves."""

from __future__ import annotations

from datetime import date, timedelta
from fractions import Fraction

import pytest

from book_guard import _quotas

MON = date(2026, 11, 2)
WEEK = [MON + timedelta(days=i) for i in range(7)]
TUE, WED, THU, FRI, SAT, SUN = WEEK[1:]
F = Fraction


@pytest.mark.parametrize(
    ("day", "weight", "weekend"),
    [
        (MON, 30, False),
        (TUE, 15, False),
        (WED, 15, False),
        (THU, 15, False),
        (FRI, 30, False),
        (SAT, 50, True),
        (SUN, 50, True),
    ],
)
def test_every_weekday_class(day: date, weight: int, *, weekend: bool) -> None:
    assert _quotas.weight(day) == weight
    assert _quotas.is_weekend(day) is weekend


def test_split_rescales_by_weight() -> None:
    # One week weighs 205: 246 pages is 1.2 times each weight (Sat/Sun 60).
    quotas, unspread = _quotas.split(Fraction(246), WEEK)
    assert quotas == {d: Fraction(6, 5) * _quotas.weight(d) for d in WEEK}
    assert unspread == 0


def test_split_caps_weekends_and_moves_the_rest_to_mon_fri() -> None:
    # 500 would be 121.95 a weekend day: they sit at 60, Mon-Fri share 380
    # in their 30:15:15:15:30 ratio (105 units).
    quotas, unspread = _quotas.split(Fraction(500), WEEK)
    assert (quotas[SAT], quotas[SUN], unspread) == (F(60), F(60), F(0))
    assert quotas[MON] == Fraction(30 * 380, 105)
    assert quotas[TUE] == Fraction(15 * 380, 105)
    assert sum(quotas.values()) == 500


def test_split_with_only_weekends_leaves_the_rest_unspread() -> None:
    quotas, unspread = _quotas.split(Fraction(200), [SAT, SUN])
    assert quotas == {SAT: 60, SUN: 60}
    assert unspread == 80


def test_split_over_no_day_spreads_nothing() -> None:
    assert _quotas.split(Fraction(7), []) == ({}, Fraction(7))


def test_surplus_comes_off_mon_fri_evenly_never_weekends() -> None:
    quotas = {d: Fraction(_quotas.weight(d)) for d in WEEK}
    # 5 days lose 3 each; the weekends keep their 50.
    assert _quotas.cut_weekdays(quotas, WEEK, Fraction(15)) == 15
    assert quotas == {
        MON: 27,
        TUE: 12,
        WED: 12,
        THU: 12,
        FRI: 27,
        SAT: 50,
        SUN: 50,
    }


def test_surplus_water_fills_down_to_zero_and_returns_what_fit() -> None:
    quotas = {d: Fraction(_quotas.weight(d)) for d in WEEK}
    # Mon-Fri hold 105; the other 95 is left for the caller to carry.
    assert _quotas.cut_weekdays(quotas, WEEK, Fraction(200)) == 105
    assert [quotas[d] for d in WEEK] == [0, 0, 0, 0, 0, 50, 50]


def test_debt_fills_weekends_evenly_up_to_the_cap() -> None:
    quotas = {SAT: Fraction(50), SUN: Fraction(56), MON: Fraction(30)}
    shares, unplaced = _quotas.fill_weekends(quotas, [SAT, SUN, MON], Fraction(6))
    assert (shares, unplaced) == ({SAT: F(3), SUN: F(3)}, F(0))
    # Sun has room for 4 only: Sat takes the rest up to its own 10.
    shares, unplaced = _quotas.fill_weekends(quotas, [SAT, SUN], Fraction(12))
    assert (shares, unplaced) == ({SAT: F(8), SUN: F(4)}, F(0))
    shares, unplaced = _quotas.fill_weekends(quotas, [SAT, SUN], Fraction(20))
    assert (shares, unplaced) == ({SAT: F(10), SUN: F(4)}, F(6))
    assert quotas == {SAT: 50, SUN: 56, MON: 30}


def test_debt_with_no_weekend_left_is_all_unplaced() -> None:
    full = {SAT: Fraction(60)}
    assert _quotas.fill_weekends(full, [SAT], F(5)) == ({SAT: F(0)}, F(5))
    assert _quotas.fill_weekends({}, [MON], F(5)) == ({}, F(5))
