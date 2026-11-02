# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A focus project switches the gate off like a sick day: 0 pages asked, never
locks, counts as kept -- and fails closed when ``focus_project`` is missing."""

from __future__ import annotations

from datetime import date, timedelta
import logging
import sys
from types import SimpleNamespace
from typing import TYPE_CHECKING

from book_guard import _bonus, _cli, _focus, _ledger, _sick
from book_guard._daily_lock import kept
from book_guard._render import status_lines
from book_guard._state import snapshot
from book_guard._state_json import to_json
from book_guard.tests._flow_helpers import LOCKED_DAY

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths
    from book_guard.tests.conftest import SickPool

REAL_STANDS_DOWN = _focus.stands_down
REAL_PROJECT_NAME = _focus.project_name
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


def test_a_focus_day_says_focus_in_every_surface(
    bg_paths: Paths, focus_pool: set[date]
) -> None:
    focus_pool.add(LOCKED_DAY)

    snap = snapshot(bg_paths, today=LOCKED_DAY)

    assert snap.reason == "focus day: Test project"
    assert _sick.focus_name(LOCKED_DAY) == "Test project"
    assert "Today is a focus day (Test project): no pages asked" in "\n".join(
        status_lines(snap)
    )
    assert to_json(bg_paths, snap)["focus_name"] == "Test project"


def test_a_real_sick_day_keeps_its_text_even_inside_a_project(
    bg_paths: Paths, sick_pool: SickPool, focus_pool: set[date]
) -> None:
    sick_pool[LOCKED_DAY] = frozenset()
    focus_pool.add(LOCKED_DAY)

    snap = snapshot(bg_paths, today=LOCKED_DAY)

    assert snap.reason == "today is a sick day"
    assert _sick.focus_name(LOCKED_DAY) is None
    assert "Today is a sick day" in "\n".join(status_lines(snap))


def test_an_ordinary_day_has_no_focus_name(bg_paths: Paths) -> None:
    snap = snapshot(bg_paths, today=LOCKED_DAY)

    assert _sick.focus_name(LOCKED_DAY) is None
    assert to_json(bg_paths, snap)["focus_name"] is None


def test_the_project_name_comes_from_the_package(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    project = SimpleNamespace(name="HackerRank prep")
    fake = SimpleNamespace(active=lambda day: project if day == NEXT else None)
    monkeypatch.setitem(sys.modules, "focus_project", fake)

    assert REAL_PROJECT_NAME(NEXT) == "HackerRank prep"
    assert REAL_PROJECT_NAME(LOCKED_DAY) == "focus project"
    monkeypatch.setitem(sys.modules, "focus_project", None)
    assert REAL_PROJECT_NAME(NEXT) == "focus project"


def test_ask_says_focus_day_not_sick_day(
    focus_pool: set[date], capsys: pytest.CaptureFixture[str]
) -> None:
    focus_pool.add(LOCKED_DAY)
    day = LOCKED_DAY.isoformat()

    assert _cli.main(["ask", "--date", day]) == 0
    detail = capsys.readouterr().out
    assert _cli.main(["ask", "--date", day, "--week"]) == 0
    week = capsys.readouterr().out

    assert "focus day (Test project): asks nothing" in detail
    assert "focus day (Test project), read" in week
    assert "sick day" not in detail + week


def test_ask_keeps_sick_day_text_inside_a_project(
    sick_pool: SickPool, focus_pool: set[date], capsys: pytest.CaptureFixture[str]
) -> None:
    sick_pool[LOCKED_DAY] = frozenset()
    focus_pool.add(LOCKED_DAY)

    assert _cli.main(["ask", "--date", LOCKED_DAY.isoformat()]) == 0

    out = capsys.readouterr().out
    assert "sick day: asks nothing" in out
    assert "focus day" not in out
