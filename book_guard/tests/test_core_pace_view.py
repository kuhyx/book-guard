# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Any day's requirement (_pace_view), the app's inputs and the golden fixture."""

from __future__ import annotations

from datetime import date
import json
from pathlib import Path

import pytest

from book_guard import _pace_inputs
from book_guard._ledger import CREDIT, Entry, Ledger
from book_guard._pace_view import (
    FUTURE,
    PAST,
    TODAY,
    Simulation,
    cached,
    month_of,
    parse_simulation,
    views,
    week_of,
)
from scripts import pace_goldens

Out = pytest.CaptureFixture[str]
TODAY_D = date(2026, 10, 15)  # a Thursday
FIXTURE = Path(__file__).resolve().parents[2] / "app/test/fixtures/pace_goldens.json"


def _ledger(pages: dict[date, int]) -> Ledger:
    return Ledger([Entry(f"c{d}", CREDIT, d.isoformat(), n) for d, n in pages.items()])


def _never(_day: date) -> bool:
    return False


# -- parsing and spans ------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "sim"),
    [
        ("5", Simulation(TODAY_D, 5)),
        ("+15", Simulation(TODAY_D, 15)),
        (" -20@2026-10-17 ", Simulation(date(2026, 10, 17), -20)),
    ],
)
def test_parse_simulation(text: str, sim: Simulation) -> None:
    assert parse_simulation(text, TODAY_D) == sim


@pytest.mark.parametrize(
    ("text", "error"),
    [("abc", "expected"), ("5@2026-10-14", "starts today or later")],
)
def test_parse_simulation_refuses(text: str, error: str) -> None:
    with pytest.raises(ValueError, match=error):
        parse_simulation(text, TODAY_D)


def test_spans_and_cache() -> None:
    assert week_of(TODAY_D)[0] == date(2026, 10, 12)
    assert len(week_of(TODAY_D)) == 7
    assert (month_of(TODAY_D)[0], month_of(TODAY_D)[-1]) == (
        date(2026, 10, 1),
        date(2026, 10, 31),
    )
    calls: list[date] = []

    def is_free(day: date) -> bool:
        calls.append(day)
        return True

    check = cached(is_free)
    assert check(TODAY_D)
    assert check(TODAY_D)
    assert calls == [TODAY_D]


# -- the walk -----------------------------------------------------------------


def test_past_today_and_future() -> None:
    ledger = _ledger({date(2026, 10, 13): 20, TODAY_D: 5})
    found = views(ledger, TODAY_D, week_of(TODAY_D), (_never, frozenset()))
    assert [v.kind for v in found] == [PAST] * 3 + [TODAY] + [FUTURE] * 3
    tuesday, today, friday = found[1], found[3], found[4]
    assert (tuesday.credited, tuesday.assumed) == (20, 20)
    assert today.credited == 5
    assert today.assumed == max(5, today.required)
    assert (friday.credited, friday.assumed) == (0, friday.required)
    assert not friday.old_rule
    assert friday.counted


def test_only_past_days_and_no_days() -> None:
    assert views(_ledger({}), TODAY_D, [], (_never, frozenset())) == []
    (view,) = views(_ledger({}), TODAY_D, [date(2026, 10, 5)], (_never, frozenset()))
    assert (view.kind, view.old_rule) == (PAST, True)


def test_simulation_moves_later_days() -> None:
    days = week_of(TODAY_D)
    base = views(_ledger({}), TODAY_D, days, (_never, frozenset()))
    sim = Simulation(date(2026, 10, 16), 30)
    moved = views(_ledger({}), TODAY_D, days, (_never, frozenset()), sim)
    friday = moved[4]
    assert (friday.simulated, friday.assumed) == (30, base[4].required + 30)
    # the surplus eases what the weekend cannot hold
    assert moved[5].pace.ask.debt_unplaced < base[5].pace.ask.debt_unplaced
    gone = views(
        _ledger({}), TODAY_D, days, (_never, frozenset()), Simulation(TODAY_D, -999)
    )
    assert gone[3].assumed == 0


# -- the app's inputs and the golden fixture -----------------------------------


def test_pace_inputs_carry_credits_rules_and_free_days() -> None:
    ledger = _ledger({date(2026, 9, 1): 99, date(2026, 10, 3): 10, TODAY_D: 5})
    sick = frozenset({date(2026, 10, 20), date(2030, 1, 1)})
    found = _pace_inputs.pace_inputs(ledger, TODAY_D, lambda d: d.day == 1, sick)
    assert found["sick_days"] == ["2026-10-20"]
    assert found["today"] == "2026-10-15"
    assert found["credits"] == {"2026-10-03": 10, "2026-10-15": 5}
    assert found["free_days"][0] == "2026-10-01"
    assert found["free_days"][-1] == "2027-12-01"
    assert found["rules"]["quota_switch"] == "2026-10-12"
    assert found["rules"]["weekend_days"] == [5, 6]


def test_pace_goldens_are_current(tmp_path: Path, capsys: Out) -> None:
    """A stale fixture fails: rerun python -m scripts.pace_goldens after a plan change."""
    fresh = tmp_path / "goldens.json"
    assert pace_goldens.main([str(fresh)]) == 0
    capsys.readouterr()
    assert json.loads(fresh.read_text(encoding="utf-8")) == json.loads(
        FIXTURE.read_text(encoding="utf-8")
    ), (
        "app/test/fixtures/pace_goldens.json is stale: rerun python -m scripts.pace_goldens"
    )
    assert fresh.read_bytes() == FIXTURE.read_bytes()
