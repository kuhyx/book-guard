# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""On a sick day the gate stands down; the hour still takes the usual reading."""

from __future__ import annotations

import dataclasses
from datetime import UTC, date, datetime
from typing import TYPE_CHECKING

from book_guard import _bonus, _ledger
from book_guard._ask import Ask
from book_guard._autogrant import auto_grant
from book_guard._pace_text import detail, row
from book_guard._pace_view import TODAY, DayView
from book_guard._render import status_lines
from book_guard._state import snapshot
from book_guard._state_json import to_json
from book_guard.tests._flow_helpers import LOCKED_DAY, make_pace, make_snap

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard.tests.conftest import SickPool

TUE = date(2026, 10, 13)
NOON = datetime(2026, 10, 13, 10, 0, tzinfo=UTC).timestamp()


def _sick(pool: SickPool, *days: date) -> None:
    pool.update(dict.fromkeys(days, frozenset()))


def test_a_sick_day_never_locks_and_says_why(
    bg_paths: Paths, sick_pool: SickPool
) -> None:
    assert snapshot(bg_paths, today=LOCKED_DAY).locked
    _sick(sick_pool, LOCKED_DAY)
    snap = snapshot(bg_paths, today=LOCKED_DAY)
    assert (snap.locked, snap.reason, snap.sick_today) == (
        False,
        "today is a sick day",
        True,
    )
    assert snap.pace.ask.required == 0
    assert snap.pace.ask.bonus_at == 18


def test_the_reason_names_the_sick_day_even_on_pace(bg_paths: Paths) -> None:
    snap = snapshot(
        bg_paths, today=date(2026, 10, 2), sick=frozenset({date(2026, 10, 2)})
    )
    assert snap.reason == "today is a sick day"


def test_state_json_tells_sick_from_free(bg_paths: Paths, sick_pool: SickPool) -> None:
    _sick(sick_pool, LOCKED_DAY)
    doc = to_json(bg_paths, snapshot(bg_paths, today=LOCKED_DAY))
    assert doc["sick_today"] is True
    assert (doc["pace"]["today_quota"], doc["pace"]["today_required"]) == (0, 18)
    assert doc["pace_inputs"]["sick_days"] == [LOCKED_DAY.isoformat()]
    assert LOCKED_DAY.isoformat() not in doc["pace_inputs"]["free_days"]


def test_a_sick_day_gets_no_hour_without_reading(
    bg_paths: Paths, sick_pool: SickPool
) -> None:
    _sick(sick_pool, TUE)
    assert auto_grant(bg_paths, today=TUE, now=NOON) is None
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert _bonus.day_requirement(ledger, TUE) == 18


def test_status_says_sick_and_what_still_earns_the_hour() -> None:
    snap = dataclasses.replace(make_snap(), sick_days=frozenset({date(2026, 10, 5)}))
    pace = dataclasses.replace(make_pace(), pages_today=4, ask=Ask(bonus_at=30))
    lines = status_lines(dataclasses.replace(snap, pace=pace))
    assert lines[3] == (
        "Today is a sick day: no pages asked, its share moves to the days left "
        "(4 read; 30 earn the +1h)"
    )
    earned = dataclasses.replace(pace, ask=Ask(bonus_at=30, bonus=True))
    lines = status_lines(dataclasses.replace(snap, pace=earned))
    assert lines[3].endswith("(4 read; bonus earned)")


def test_ask_shows_a_sick_day() -> None:
    pace = dataclasses.replace(make_pace(), ask=Ask(bonus_at=17))
    view = DayView(date(2026, 10, 15), TODAY, pace, 6, 6, free=False, sick=True)
    assert row(view).endswith("sick day, read 6")
    assert detail(view)[1] == (
        "  sick day: asks nothing, its share moves to the days left "
        "(reading 17 pages still earns the +1h)"
    )
