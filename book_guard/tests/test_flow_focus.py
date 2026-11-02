# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A focus project switches the gate off like a sick day: 0 pages asked, never
locks, counts as kept -- and fails closed when ``focus_project`` is missing."""

from __future__ import annotations

from datetime import date, timedelta
import logging
import sys
from types import SimpleNamespace
from typing import TYPE_CHECKING

from book_guard import _bonus, _focus, _ledger, _sick
from book_guard._daily_lock import kept
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import LOCKED_DAY

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths
    from book_guard.tests.conftest import SickPool

REAL_STANDS_DOWN = _focus.stands_down
"""Captured at import: the autouse stub replaces the module attribute."""
NEXT = LOCKED_DAY + timedelta(days=1)


def test_a_focus_day_never_locks_and_asks_nothing(
    bg_paths: Paths, focus_pool: set[date]
) -> None:
    assert snapshot(bg_paths, today=LOCKED_DAY).locked
    focus_pool.add(LOCKED_DAY)

    snap = snapshot(bg_paths, today=LOCKED_DAY)

    assert (snap.locked, snap.sick_today) == (False, True)
    assert snap.pace.ask.required == 0
    assert LOCKED_DAY in snap.sick_days


def test_a_focus_day_counts_as_kept_yesterday(
    bg_paths: Paths, focus_pool: set[date]
) -> None:
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    yesterday = date(2026, 10, 27)
    sick = _sick.standing_down(yesterday)
    assert kept(ledger, yesterday, lambda _d: False, sick=sick) is False

    focus_pool.add(yesterday)
    sick = _sick.standing_down(yesterday)

    assert kept(ledger, yesterday, lambda _d: False, sick=sick) is True


def test_the_bonus_requirement_sees_the_focus_day(
    bg_paths: Paths, focus_pool: set[date]
) -> None:
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    before = _bonus.day_requirement(ledger, LOCKED_DAY)
    focus_pool.add(LOCKED_DAY)

    # Like a sick day the requirement for the hour is kept, only the ask is 0.
    assert _bonus.day_requirement(ledger, LOCKED_DAY) == before


def test_standing_down_unions_sick_and_focus(
    sick_pool: SickPool, focus_pool: set[date]
) -> None:
    sick_pool[LOCKED_DAY] = frozenset()
    focus_pool.add(NEXT)

    assert _sick.standing_down(LOCKED_DAY) == {LOCKED_DAY, NEXT}


def test_the_focus_window_is_bounded_around_the_anchor(
    focus_pool: set[date],
) -> None:
    near, far = LOCKED_DAY + timedelta(days=60), LOCKED_DAY + timedelta(days=90)
    focus_pool.update({near, far})

    assert _sick.standing_down(LOCKED_DAY) == {near}


def test_standing_down_defaults_to_today(focus_pool: set[date]) -> None:
    focus_pool.add(date.today())

    assert date.today() in _sick.standing_down()


def test_stands_down_asks_the_package(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = SimpleNamespace(stands_down=lambda gate, day: (gate, day) == ("x", NEXT))
    monkeypatch.setitem(sys.modules, "focus_project", fake)

    assert REAL_STANDS_DOWN("x", NEXT) is True
    assert REAL_STANDS_DOWN("x", LOCKED_DAY) is False


def test_a_missing_package_fails_closed_and_logs_once(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    monkeypatch.setitem(sys.modules, "focus_project", None)
    monkeypatch.setattr(_focus, "_warned", set())

    with caplog.at_level(logging.ERROR, logger=_focus.__name__):
        assert REAL_STANDS_DOWN("book", LOCKED_DAY) is False
        assert REAL_STANDS_DOWN("book", NEXT) is False

    errors = [r for r in caplog.records if r.levelno == logging.ERROR]
    assert len(errors) == 1
    assert "focus_project is not importable" in errors[0].getMessage()
