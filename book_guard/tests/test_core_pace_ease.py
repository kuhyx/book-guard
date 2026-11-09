# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""An eased day: pages off its number, spread over the rest of the month."""

from __future__ import annotations

from datetime import date, timedelta
from fractions import Fraction
from typing import TYPE_CHECKING

import pytest

from book_guard import _bonus, _daily_lock, _ease, _pace
from book_guard._constants import RESPLIT_DATE
from book_guard._ledger import EASE, Entry, Ledger
from book_guard.tests.test_core_pace import _credit, _never

if TYPE_CHECKING:
    from book_guard._plan import MonthPlan

_MON = date(2026, 11, 9)
_NOV1 = date(2026, 11, 1)
_NOV_END = date(2026, 11, 30)


def _ease_row(day: date, pages: int, *, entry_id: str = "") -> Entry:
    return Entry(
        entry_id=entry_id or f"ease:{day}",
        kind=EASE,
        day=day.isoformat(),
        amount=pages,
        detail={"reason": "reader failed"},
    )


def _ledger(*rows: Entry) -> Ledger:
    """October settled to the page (balance 0), then ``rows`` in November."""
    return Ledger([_credit("2026-10-31", 1000), *rows])


def _pace_on(
    ledger: Ledger, day: date, sick: frozenset[date] = frozenset()
) -> _pace.Pace:
    return _pace.compute_pace(ledger, day, _never, sick=sick)


def _plan(ledger: Ledger, until: date) -> MonthPlan:
    cal = _pace._Calendar(_never, frozenset())
    return _pace._plan(ledger, _NOV1, cal, 0, until)[0]


def test_the_reader_sums_positive_rows_by_day() -> None:
    ledger = Ledger(
        [
            _ease_row(_MON, 2),
            _ease_row(_MON, 3, entry_id="ease:again"),
            _ease_row(_MON + timedelta(days=1), 0),
            _ease_row(_MON + timedelta(days=2), -4),
            Entry("ease:junk", EASE, "not-a-day", 5),
            _credit("2026-11-09", 50),
        ]
    )
    assert _ease.eased_days(ledger) == {_MON: 5}


def test_an_eased_day_asks_its_share_less_the_pages() -> None:
    plain = _pace_on(_ledger(), _MON)
    eased = _pace_on(_ledger(_ease_row(_MON, 2)), _MON)
    assert plain.ask.required > 2
    assert eased.ask.required == plain.ask.required - 2
    assert eased.ask.bonus_at == eased.ask.required
    # The line moves with the number: the pages read before it plus today's.
    assert eased.required == plain.required - 2


def test_reading_the_eased_number_is_on_pace() -> None:
    plain = _pace_on(_ledger(), _MON)
    read = plain.ask.required - 2
    ledger = _ledger(_credit(_MON.isoformat(), read), _ease_row(_MON, 2))
    pace = _pace_on(ledger, _MON)
    assert (pace.pages_today, pace.behind) == (read, 0)
    assert _daily_lock.kept(ledger, _MON, _never, sick=frozenset())


def test_without_the_ease_the_same_reading_is_short() -> None:
    plain = _pace_on(_ledger(), _MON)
    ledger = _ledger(_credit(_MON.isoformat(), plain.ask.required - 2))
    assert _pace_on(ledger, _MON).behind == 2
    assert not _daily_lock.kept(ledger, _MON, _never, sick=frozenset())


def test_the_pages_spread_over_the_days_left_and_the_target_holds() -> None:
    plain = _plan(_ledger(), _MON)
    eased = _plan(_ledger(_ease_row(_MON, 2)), _MON)
    later = [d for d in plain.quotas if d > _MON]
    assert eased.quotas[_MON] == plain.quotas[_MON] - 2
    # Weekends sit at their cap and take none; the weekdays take it all.
    assert all(eased.quotas[d] >= plain.quotas[d] for d in later)
    assert any(eased.quotas[d] > plain.quotas[d] for d in later)
    assert sum(eased.quotas[d] - plain.quotas[d] for d in later) == 2
    assert eased.target == plain.target == 1000


def test_the_next_morning_splits_what_was_not_read() -> None:
    plain = _pace_on(_ledger(), _MON)
    read = plain.ask.required - 2
    done = _ledger(_credit(_MON.isoformat(), read), _ease_row(_MON, 2))
    tomorrow = _MON + timedelta(days=1)
    after = _pace_on(done, tomorrow)
    # Same as anyone who read that much: the 2 pages are not forgiven.
    bare = _ledger(_credit(_MON.isoformat(), read))
    assert after.ask.required == _pace_on(bare, tomorrow).ask.required
    kept = _ledger(_credit(_MON.isoformat(), plain.ask.required))
    assert after.ask.required >= _pace_on(kept, tomorrow).ask.required
    assert after.target == 1000


def test_an_ease_past_the_share_floors_at_zero() -> None:
    pace = _pace_on(_ledger(_ease_row(_MON, 500)), _MON)
    assert (pace.ask.required, pace.behind) == (0, 0)
    assert _plan(_ledger(_ease_row(_MON, 500)), _MON).target == 1000


def test_the_last_counted_day_eases_into_the_unspread() -> None:
    plan = _plan(_ledger(_ease_row(_NOV_END, 2)), _NOV_END)
    assert plan.target == 1000
    assert plan.unspread == Fraction(2)


def test_a_past_eased_day_reads_as_eased() -> None:
    plain = _pace_on(_ledger(), _MON)
    day = _MON - timedelta(days=3)
    ledger = _ledger(_ease_row(day, 2))
    assert (
        _pace_on(ledger, day).ask.required == _pace_on(_ledger(), day).ask.required - 2
    )
    assert plain.target == _pace_on(ledger, _MON).target == 1000


def test_an_ease_before_the_resplit_changes_nothing() -> None:
    day = RESPLIT_DATE - timedelta(days=2)
    rows = [_credit("2026-10-05", 100)]
    plain = _pace_on(Ledger(rows), day)
    eased = _pace_on(Ledger([*rows, _ease_row(day, 2)]), day)
    assert eased == plain


def test_an_ease_on_a_future_day_waits_for_its_morning() -> None:
    soon = _MON + timedelta(days=3)
    assert _pace_on(_ledger(_ease_row(soon, 2)), _MON) == _pace_on(_ledger(), _MON)
    assert (
        _pace_on(_ledger(_ease_row(soon, 2)), soon).ask.required
        == _pace_on(_ledger(), soon).ask.required - 2
    )


def test_a_sick_days_bonus_threshold_is_eased() -> None:
    sick = frozenset({_MON})
    plain = _pace_on(_ledger(), _MON, sick)
    eased = _pace_on(_ledger(_ease_row(_MON, 2)), _MON, sick)
    assert eased.ask.required == 0
    assert eased.ask.bonus_at == plain.ask.bonus_at - 2


def test_the_year_balance_does_not_shrink_for_an_eased_month() -> None:
    nov = _MON.replace(day=9)
    dec = date(2026, 12, 1)
    ledger = Ledger([_credit("2026-10-31", 1000), _credit(nov.isoformat(), 900)])
    eased = Ledger([*ledger.entries, _ease_row(nov, 2)])
    assert _pace_on(eased, dec) == _pace_on(ledger, dec)


def test_the_bonus_requirement_is_the_eased_one() -> None:
    plain = _bonus.day_requirement(_ledger(), _MON)
    eased = _bonus.day_requirement(_ledger(_ease_row(_MON, 2)), _MON)
    assert eased == plain - 2


@pytest.mark.parametrize("pages", [0, -1])
def test_no_pages_no_ease(pages: int) -> None:
    ledger = _ledger(_ease_row(_MON, pages))
    assert _pace_on(ledger, _MON) == _pace_on(_ledger(), _MON)
