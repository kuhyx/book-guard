# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_pace's year balance: 1000 a month, the surplus or shortfall spread on."""

from __future__ import annotations

from datetime import date

from book_guard import _pace
from book_guard._ledger import Entry, Ledger
from book_guard.tests.test_core_pace import _credit, _never


def _on_target_through(last: date, *reads: tuple[date, int]) -> Ledger:
    """Every month from October to ``last`` read exactly its target, but ``reads``."""
    entries: list[Entry] = []
    first = date(2026, 10, 1)
    override = dict(reads)
    while first <= last:
        today = max(first, date(2026, 10, 2))
        target = _pace.compute_pace(Ledger(list(entries)), today, _never).target
        entries.append(_credit(today.isoformat(), override.get(first, target)))
        first = _pace._next_month(first)
    return Ledger(entries)


def test_surplus_spreads_over_the_rest_of_the_year() -> None:
    january = date(2027, 1, 1)
    ledger = _on_target_through(date(2027, 2, 1), (january, 1012))
    # 12 ahead over Feb-Dec: February takes the odd page.
    assert _pace.compute_pace(ledger, date(2027, 2, 10), _never).target == 998
    assert _pace.compute_pace(ledger, date(2027, 3, 10), _never).target == 999


def test_shortfall_spreads_over_the_rest_of_the_year() -> None:
    january = date(2027, 1, 1)
    ledger = _on_target_through(date(2027, 9, 1), (january, 970))
    # 30 short over Feb-Dec: Feb-Sep take 3, Oct-Dec 2.
    assert _pace.compute_pace(ledger, date(2027, 2, 10), _never).target == 1003
    assert _pace.compute_pace(ledger, date(2027, 9, 10), _never).target == 1003
    assert _pace.compute_pace(ledger, date(2027, 10, 10), _never).target == 1002


def test_december_balance_lands_on_january() -> None:
    december = date(2026, 12, 1)
    ledger = _on_target_through(date(2027, 1, 1), (december, 950))
    assert _pace.compute_pace(ledger, date(2027, 1, 10), _never).target == 1050
    assert _pace.compute_pace(ledger, date(2027, 2, 10), _never).target == 1000


def test_target_never_goes_below_zero() -> None:
    ledger = _on_target_through(date(2027, 1, 1), (date(2027, 1, 1), 20000))
    february = _pace.compute_pace(ledger, date(2027, 2, 10), _never)
    assert (february.target, february.required, february.behind) == (0, 0, 0)


def test_share_rounds_away_from_zero() -> None:
    assert (_pace._share(12, 11), _pace._share(-12, 11)) == (2, -2)
    assert (_pace._share(0, 3), _pace._share(-22, 11)) == (0, -2)
    assert [_pace._months_left(date(2027, m, 1)) for m in (1, 2, 12)] == [1, 11, 1]
