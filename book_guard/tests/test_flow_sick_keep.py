# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A sick day that keeps ``book`` is a normal day for this gate, past or today.

Only a sick day that does not keep ``book`` stands the gate down and drops
the day's share (``sickdays.stands_down``). Every surface -- the verdict, the
plan, the bonus requirement, the app's ``pace_inputs``, ``ask`` -- sees the
same filtered set, so they can never disagree about what a kept day owes.
"""

from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING

import sickdays

from book_guard import _bonus, _cli, _ledger
from book_guard._state import snapshot
from book_guard._state_json import to_json
from book_guard.tests._flow_helpers import LOCKED_DAY, add_credit

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths
    from book_guard.tests.conftest import SickPool

KEEP_BOOK = frozenset({sickdays.LOCKER_BOOK})
KEEP_NOTHING: frozenset[str] = frozenset()
PAST_TUE = date(2026, 10, 13)
SAT = date(2026, 10, 17)
SUN = date(2026, 10, 18)


def test_a_sick_day_that_keeps_book_locks_like_any_day(
    bg_paths: Paths, sick_pool: SickPool
) -> None:
    normal = snapshot(bg_paths, today=LOCKED_DAY)
    sick_pool[LOCKED_DAY] = KEEP_BOOK
    kept = snapshot(bg_paths, today=LOCKED_DAY)
    assert (kept.locked, kept.reason, kept.sick_today) == (
        normal.locked,
        normal.reason,
        False,
    )
    assert kept.locked
    assert kept.pace == normal.pace


def test_keeping_only_other_lockers_still_stands_book_down(
    bg_paths: Paths, sick_pool: SickPool
) -> None:
    sick_pool[LOCKED_DAY] = frozenset(
        {sickdays.LOCKER_LEETCODE, sickdays.LOCKER_WORKOUT}
    )
    snap = snapshot(bg_paths, today=LOCKED_DAY)
    assert (snap.locked, snap.reason, snap.sick_today) == (
        False,
        "today is a sick day",
        True,
    )
    assert snap.pace.ask.required == 0


def test_a_past_kept_sick_day_is_owed_like_a_normal_one(
    bg_paths: Paths, sick_pool: SickPool
) -> None:
    normal = snapshot(bg_paths, today=LOCKED_DAY).pace
    sick_pool[PAST_TUE] = KEEP_BOOK
    assert snapshot(bg_paths, today=LOCKED_DAY).pace == normal
    sick_pool[PAST_TUE] = KEEP_NOTHING
    assert snapshot(bg_paths, today=LOCKED_DAY).pace.behind < normal.behind


def test_pace_inputs_list_only_the_days_book_stands_down(
    bg_paths: Paths, sick_pool: SickPool
) -> None:
    sick_pool.update({PAST_TUE: KEEP_NOTHING, LOCKED_DAY: KEEP_BOOK})
    doc = to_json(bg_paths, snapshot(bg_paths, today=LOCKED_DAY))
    assert doc["sick_today"] is False
    assert doc["pace_inputs"]["sick_days"] == [PAST_TUE.isoformat()]


def test_the_bonus_requirement_matches_the_gate_after_a_kept_day(
    bg_paths: Paths, sick_pool: SickPool
) -> None:
    # 4 pages behind on Saturday: Sunday standing down moves Saturday's ceil
    # of the debt share from 1 to 2 pages; a Sunday that keeps book does not.
    add_credit(bg_paths, "2026-10-12", 696)
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    normal = _bonus.day_requirement(ledger, SAT)
    sick_pool[SUN] = KEEP_NOTHING
    excused = _bonus.day_requirement(ledger, SAT)
    sick_pool[SUN] = KEEP_BOOK
    kept = _bonus.day_requirement(ledger, SAT)
    assert (normal, excused, kept) == (58, 59, 58)
    assert kept == snapshot(bg_paths, today=SAT).pace.ask.bonus_at


def test_ask_shows_a_kept_sick_day_as_a_normal_day(
    sick_pool: SickPool, capsys: pytest.CaptureFixture[str]
) -> None:
    sick_pool[PAST_TUE] = KEEP_NOTHING
    assert _cli.main(["ask", "--date", PAST_TUE.isoformat()]) == 0
    assert "sick day" in capsys.readouterr().out
    sick_pool[PAST_TUE] = KEEP_BOOK
    assert _cli.main(["ask", "--date", PAST_TUE.isoformat()]) == 0
    assert "sick day" not in capsys.readouterr().out
