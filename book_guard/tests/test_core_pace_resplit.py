# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""From the resplit: every morning re-splits what is left of the month."""

from __future__ import annotations

from datetime import date, timedelta
from fractions import Fraction
import math

from book_guard import _pace
from book_guard._constants import RESPLIT_DATE, WEEKEND_CAP_PAGES
from book_guard._ledger import CREDIT, Entry, Ledger
from book_guard._quotas import split
from book_guard.tests.test_core_pace import _credit, _never

_SUN = RESPLIT_DATE  # Sun 2026-10-18
_MON = _SUN + timedelta(days=1)
_OCT_END = date(2026, 10, 31)
_NOV1 = date(2026, 11, 1)


def _days(first: date, last: date) -> list[date]:
    return [first + timedelta(days=i) for i in range((last - first).days + 1)]


def _read_before(total: int) -> Ledger:
    """``total`` pages credited on Oct 17, the day before the resplit."""
    return Ledger([_credit("2026-10-17", total)])


def _pace_on(
    ledger: Ledger, day: date, sick: frozenset[date] = frozenset()
) -> _pace.Pace:
    return _pace.compute_pace(ledger, day, _never, sick=sick)


def test_the_morning_splits_what_is_left_by_weight() -> None:
    # 900 of October's 1000 read: 100 left over Oct 18-31 (410 units).
    pace = _pace_on(_read_before(900), _SUN)
    expected = math.ceil(Fraction(100 * 50, 410))
    assert pace.ask.required == expected == 13
    # A weekend loses surplus too: before the resplit it never did.
    assert pace.required == 900 + expected
    assert pace.behind == expected


def test_reading_today_does_not_move_todays_number() -> None:
    ledger = _read_before(900)
    ledger.entries.append(_credit(_SUN.isoformat(), 10))
    pace = _pace_on(ledger, _SUN)
    assert (pace.ask.required, pace.pages_today, pace.behind) == (13, 10, 3)


def test_meeting_todays_number_is_on_pace() -> None:
    ledger = _read_before(900)
    ledger.entries.append(_credit(_SUN.isoformat(), 13))
    assert _pace_on(ledger, _SUN).behind == 0


def test_a_debt_is_resplit_and_weekends_stay_capped() -> None:
    pace = _pace_on(Ledger(), _SUN)
    assert pace.ask.required == WEEKEND_CAP_PAGES
    # Monday takes the weekdays' share of 1000 - 4 capped weekends.
    monday = _pace_on(Ledger(), _MON)
    days = _days(_MON, _OCT_END)
    left = Fraction(1000 - 0)
    assert monday.ask.required == math.ceil(split(left, days)[0][_MON])


def test_yesterdays_shortfall_raises_every_later_day() -> None:
    met = Ledger([_credit("2026-10-17", 900), _credit(_SUN.isoformat(), 13)])
    short = Ledger([_credit("2026-10-17", 900)])
    assert _pace_on(short, _MON).ask.required > _pace_on(met, _MON).ask.required
    # Exactly the split of what is left: 100 over Oct 19-31 (360 units).
    assert _pace_on(short, _MON).ask.required == math.ceil(Fraction(100 * 30, 360))


def test_a_month_read_ahead_asks_nothing() -> None:
    pace = _pace_on(_read_before(1000), _SUN)
    assert (pace.ask.required, pace.behind) == (0, 0)


def test_a_sick_day_is_excused_and_not_resplit() -> None:
    sick = frozenset({_SUN})
    pace = _pace_on(_read_before(900), _SUN, sick)
    assert pace.ask.required == 0
    assert pace.ask.bonus_at == 13
    # Monday splits 100 - Sunday's excused 100*50/410 over 360 units.
    monday = _pace_on(_read_before(900), _MON, sick)
    left = 100 - Fraction(100 * 50, 410)
    assert monday.ask.required == math.ceil(left * 30 / 360) == 8
    assert monday.target == math.ceil(1000 - Fraction(100 * 50, 410))


def test_the_target_is_the_month_less_its_sick_days() -> None:
    ledger = Ledger([_credit("2026-10-05", 300), _credit("2026-10-17", 200)])
    for day in (_SUN, _MON, _OCT_END):
        assert _pace_on(ledger, day).target == 1000


def test_days_before_the_resplit_are_untouched() -> None:
    ledger = Ledger([_credit("2026-10-05", 300)])
    before = _pace_on(ledger, RESPLIT_DATE - timedelta(days=1))
    # The old rule still asks Saturday its weekend share plus debt.
    assert before.ask.required == WEEKEND_CAP_PAGES
    assert before.passed_today is False


def test_a_whole_new_month_splits_its_target_each_morning() -> None:
    ledger = Ledger([_credit("2026-10-17", 1000)])
    nov = _days(_NOV1, date(2026, 11, 30))
    pace = _pace_on(ledger, _NOV1)
    assert pace.carried_debt == pace.carried_credit == 0
    assert pace.ask.required == math.ceil(split(Fraction(1000), nov)[0][_NOV1])
    ledger.entries.append(
        Entry("credit:nov1", CREDIT, _NOV1.isoformat(), pace.ask.required)
    )
    second = _pace_on(ledger, _NOV1 + timedelta(days=1))
    left = Fraction(1000 - pace.ask.required)
    assert second.ask.required == math.ceil(split(left, nov[1:])[0][nov[1]])
