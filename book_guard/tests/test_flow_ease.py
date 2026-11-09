# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Easing a day: the action, the lock, and what the app is told."""

from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING

from book_guard import _actions, _ledger
from book_guard._ledger import EASE
from book_guard._state import snapshot
from book_guard._state_json import to_json
from book_guard.tests._flow_helpers import add_credit

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._state import Snapshot

_MON = date(2026, 11, 9)


def _never(_day: date) -> bool:
    return False


def _snap(paths: Paths, day: date = _MON) -> Snapshot:
    return snapshot(paths, today=day, is_free=_never, sick=frozenset())


def test_ease_day_appends_a_signed_row(bg_paths: Paths) -> None:
    assert _actions.ease_day(bg_paths, _MON, 2, "reader failed") is True
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    (row,) = ledger.of_kind(EASE)
    assert (row.entry_id, row.day, row.amount) == (f"ease:{_MON}", str(_MON), 2)
    assert row.detail == {"reason": "reader failed"}


def test_ease_day_only_once_a_day(bg_paths: Paths) -> None:
    assert _actions.ease_day(bg_paths, _MON, 2, "a") is True
    assert _actions.ease_day(bg_paths, _MON, 5, "b") is False
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert [e.amount for e in ledger.of_kind(EASE)] == [2]


def test_ease_day_refuses_no_pages(bg_paths: Paths) -> None:
    assert _actions.ease_day(bg_paths, _MON, 0, "x") is False
    assert _actions.ease_day(bg_paths, _MON, -3, "x") is False
    assert not bg_paths.ledger.exists()


def test_the_ease_opens_a_lock_two_pages_short(bg_paths: Paths) -> None:
    ask = _snap(bg_paths).pace.ask.required
    add_credit(bg_paths, _MON.isoformat(), ask - 2)
    before = _snap(bg_paths)
    assert (before.locked, before.pace.behind) == (True, 2)
    assert _actions.ease_day(bg_paths, _MON, 2, "reader failed") is True
    after = _snap(bg_paths)
    assert (after.locked, after.reason) == (False, "on pace")
    assert (after.pace.pages_today, after.pace.ask.required) == (ask - 2, ask - 2)
    assert after.pace.target == before.pace.target


def test_state_json_tells_the_app_the_eased_days(bg_paths: Paths) -> None:
    assert to_json(bg_paths, _snap(bg_paths))["pace_inputs"]["eased"] == {}
    _actions.ease_day(bg_paths, _MON, 2, "reader failed")
    doc = to_json(bg_paths, _snap(bg_paths))
    assert doc["pace_inputs"]["eased"] == {_MON.isoformat(): 2}
