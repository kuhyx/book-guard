# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A sick day asks nothing and its share is dropped -- never re-split."""

from __future__ import annotations

from datetime import date
import math
from typing import TYPE_CHECKING

from book_guard import _pace
from book_guard._ledger import Ledger
from book_guard._pace_view import DayView, month_of, views
from book_guard._plan import day_requirement, weekend_days
from book_guard.tests.test_core_pace import _credit, _never

if TYPE_CHECKING:
    from book_guard._plan import MonthPlan

OCT = date(2026, 10, 1)
TODAY = date(2026, 10, 16)
"""A Friday after the switch."""
WED = date(2026, 10, 21)
SAT = date(2026, 10, 24)
NONE: frozenset[date] = frozenset()
READ = Ledger([_credit("2026-10-02", 200), _credit("2026-10-12", 300)])
SHORT = Ledger([_credit("2026-10-02", 300), _credit("2026-10-13", 330)])
"""About 37 pages behind on Friday: the weekends' debt shares stay under 60."""


def _plan(
    sick: frozenset[date], until: date = TODAY, ledger: Ledger = READ
) -> MonthPlan:
    cal = _pace._Calendar(_never, sick)
    plan, _, _, _ = _pace._plan(ledger, OCT, cal, 0, until)
    return plan


def _views(ledger: Ledger, sick: frozenset[date]) -> dict[date, DayView]:
    days = [d for d in month_of(TODAY) if d >= TODAY]
    return {v.day: v for v in views(ledger, TODAY, days, (_never, sick))}


def test_a_sick_weekday_drops_exactly_its_share() -> None:
    base, sick = _plan(NONE), _plan(frozenset({WED}))
    share = base.quotas[WED]
    assert sick.excused == {WED: share}
    assert sick.quotas == {d: q for d, q in base.quotas.items() if d != WED}
    assert base.target - sick.target == share
    for day in month_of(TODAY):
        drop = share if day > WED else 0
        assert sick.line_before(day) == base.line_before(day) - drop


def test_every_other_day_asks_what_it_would_have() -> None:
    base, sick = _views(READ, NONE), _views(READ, frozenset({WED}))
    assert (sick[WED].required, sick[WED].sick, base[WED].sick) == (0, True, False)
    assert sick[WED].assumed == 0
    for day, view in base.items():
        if day == WED:
            continue
        # The projection reads each day's requirement rounded up, so the
        # baseline's sick Wednesday pays a fraction of a page of debt the
        # sick plan does not: a weekend's debt share may round one higher.
        slack = 1 if day.weekday() >= 5 else 0
        assert 0 <= sick[day].required - view.required <= slack
        # Not reading on the sick day left no debt behind it.
        assert 0 <= sick[day].pace.behind - view.pace.behind <= 1


def test_a_sick_weekend_keeps_every_quota_and_skips_the_debt() -> None:
    base = _plan(NONE, ledger=SHORT)
    sick = _plan(frozenset({SAT}), ledger=SHORT)
    assert sick.quotas == {d: q for d, q in base.quotas.items() if d != SAT}
    assert base.target - sick.target == base.quotas[SAT]
    _, well, _, _ = _pace._plan(SHORT, OCT, _pace._Calendar(_never, NONE), 0, TODAY)
    cal = _pace._Calendar(_never, frozenset({SAT}))
    _, month, _, _ = _pace._plan(SHORT, OCT, cal, 0, TODAY)
    assert SAT in weekend_days(well, TODAY)
    assert SAT not in weekend_days(month, TODAY)
    assert day_requirement(sick, month, SAT) == 0
    # The debt that already existed lands on the other weekends instead.
    sat = date(2026, 10, 17)
    assert day_requirement(sick, month, sat) > day_requirement(base, well, sat)


def test_pages_read_on_a_sick_day_count() -> None:
    day = date(2026, 10, 22)
    sick = frozenset({WED})
    idle = _pace.compute_pace(READ, day, _never, sick=sick)
    read = Ledger([*READ.entries, _credit(WED.isoformat(), 30)])
    pace = _pace.compute_pace(read, day, _never, sick=sick)
    assert (pace.pages, pace.behind) == (idle.pages + 30, idle.behind - 30)


def test_a_sick_day_earns_at_the_requirement_it_would_have_had() -> None:
    well = _pace.compute_pace(READ, WED, _never, sick=NONE)
    pace = _pace.compute_pace(READ, WED, _never, sick=frozenset({WED}))
    assert (pace.ask.required, pace.ask.bonus_at) == (0, well.ask.required)
    assert well.ask.bonus_at == well.ask.required > 0
    assert pace.days_left == well.days_left - 1


def test_last_months_sick_share_stays_out_of_the_carry() -> None:
    sick = frozenset({WED})
    oct_plan = _plan(sick, until=date(2026, 10, 31))
    owed = math.ceil(1000 - oct_plan.excused[WED]) - 500
    nov = _pace.compute_pace(READ, date(2026, 11, 3), _never, sick=sick)
    well = _pace.compute_pace(READ, date(2026, 11, 3), _never, sick=NONE)
    assert nov.carried_debt == _pace._share(owed, 2)
    assert nov.carried_debt < well.carried_debt == _pace._share(500, 2)


def test_before_the_switch_the_debt_skips_the_sick_day() -> None:
    thu = date(2026, 10, 8)
    well = _pace.compute_pace(Ledger(), thu, _never, sick=NONE)
    pace = _pace.compute_pace(Ledger(), thu, _never, sick=frozenset({thu}))
    assert pace.ask.debt_days == well.ask.debt_days - 1
    assert pace.ask.required == 0
    assert pace.target < well.target
