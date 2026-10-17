# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The 20-page day, and the debt spread over the days left before the switch."""

from __future__ import annotations

from datetime import date
import math

from book_guard import _pace
from book_guard._constants import DAILY_PASS_PAGES
from book_guard._ledger import CREDIT, Entry, Ledger
from book_guard.tests.test_core_pace import _credit, _never


def test_pages_today_sum_every_credited_session() -> None:
    ledger = Ledger(
        [
            _credit("2026-10-11", 12),
            Entry(entry_id="second", kind=CREDIT, day="2026-10-11", amount=8),
            _credit("2026-10-10", 50),
        ]
    )
    pace = _pace.compute_pace(ledger, date(2026, 10, 11), _never, sick=frozenset())
    assert pace.pages_today == DAILY_PASS_PAGES
    assert pace.passed_today
    assert pace.behind > 0


def test_nineteen_pages_do_not_pass() -> None:
    ledger = Ledger([_credit("2026-10-11", DAILY_PASS_PAGES - 1)])
    pace = _pace.compute_pace(ledger, date(2026, 10, 11), _never, sick=frozenset())
    assert (pace.pages_today, pace.passed_today) == (19, False)


def test_debt_is_split_evenly_over_the_days_left() -> None:
    pace = _pace.compute_pace(Ledger(), date(2026, 10, 11), _never, sick=frozenset())
    # Oct 11-31, today included: 21 counted days.
    assert pace.days_left == 21
    assert pace.ask.debt_per_day == math.ceil(pace.behind / 21)


def test_free_days_are_not_days_left() -> None:
    def weekend_free(day: date) -> bool:
        return day >= date(2026, 10, 30)

    pace = _pace.compute_pace(
        Ledger(), date(2026, 10, 28), weekend_free, sick=frozenset()
    )
    assert pace.days_left == 2  # Wed 28, Thu 29
    last = _pace.compute_pace(
        Ledger(), date(2026, 10, 31), weekend_free, sick=frozenset()
    )
    # No counted day left: the debt carries into November instead.
    assert (last.days_left, last.ask.debt_per_day) == (0, 0)
    assert (last.behind, last.ask.debt_unplaced) == (0, last.target)


def test_on_pace_owes_nothing_a_day() -> None:
    ledger = Ledger([_credit("2026-10-04", 400)])
    pace = _pace.compute_pace(ledger, date(2026, 10, 5), _never, sick=frozenset())
    assert (pace.behind, pace.ask.debt_per_day) == (0, 0)
