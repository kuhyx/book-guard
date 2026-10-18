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


def test_a_sick_days_share_spreads_over_the_days_left() -> None:
    sick = frozenset({_SUN})
    pace = _pace_on(_read_before(900), _SUN, sick)
    assert (pace.ask.required, pace.ask.excused) == (0, 0)
    assert pace.ask.bonus_at == 13
    # Monday splits all 100 left over Oct 19-31 (360 units): nothing excused.
    monday = _pace_on(_read_before(900), _MON, sick)
    assert monday.ask.required == math.ceil(Fraction(100 * 30, 360)) == 9
    assert monday.target == 1000


def test_a_future_sick_day_has_no_weight() -> None:
    wed = date(2026, 10, 21)
    cal = _pace._Calendar(_never, frozenset({wed}))
    plan, _, _, _ = _pace._plan(_read_before(900), _SUN.replace(day=1), cal, 0, _SUN)
    assert wed not in plan.quotas
    assert not plan.excused
    rest = [d for d in _days(_SUN, _OCT_END) if d != wed]
    assert sum(plan.quotas[d] for d in rest) == 100
    assert plan.quotas == split(Fraction(100), rest)[0] | {
        d: q for d, q in plan.quotas.items() if d < _SUN
    }


def test_the_target_is_the_whole_month_with_a_sick_day() -> None:
    ledger = Ledger([_credit("2026-10-05", 300), _credit("2026-10-17", 200)])
    for sick in (frozenset(), frozenset({_MON}), frozenset({_OCT_END})):
        for day in (_SUN, _MON, _OCT_END):
            assert _pace_on(ledger, day, sick).target == 1000


def test_a_sick_day_before_the_resplit_comes_back_on_its_morning() -> None:
    ledger = Ledger(
        [
            _credit("2026-10-05", 300),
            _credit("2026-10-14", 100),
            _credit("2026-10-17", 29),
        ]
    )
    sick = frozenset({date(2026, 10, 16)})
    seen = {
        d: (p.target, p.required, p.ask.required, p.ask.bonus_at, p.ask.excused)
        for d in (16, 17, 18)
        for p in [_pace_on(ledger, date(2026, 10, d), sick)]
    }
    # The days before the resplit replay the old rules exactly.
    assert seen[16] == (972, 527, 0, 29, 29)
    assert seen[17] == (972, 527, 60, 60, 29)
    # From the resplit the excused share is owed again, by the days left.
    assert seen[18][0] == 1000
    assert seen[18][4] == 0
    well = _pace_on(ledger, _MON, frozenset())
    assert _pace_on(ledger, _MON, sick).ask.required == well.ask.required


def test_a_month_ending_sick_carries_its_share() -> None:
    ledger = _read_before(500)
    sick = frozenset(_days(_SUN, _OCT_END))
    nov = _pace_on(ledger, date(2026, 11, 3), sick)
    assert nov.carried_debt == _pace._share(500, 2) == 250


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
