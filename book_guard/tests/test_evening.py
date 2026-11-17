# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``lock --production --evening``: the book rung of the evening chain.

The decision is the reading rung (a signed credit row with ``bonus == "1"``
that ended today), never the month's pace. These run the gate with gatelock
and the Tk view faked, like test_flow_lock.
"""

from __future__ import annotations

from dataclasses import replace
import logging
from types import SimpleNamespace
from typing import TYPE_CHECKING, Any

from book_guard import _evening, _evening_lock, _lock, _night_lockdown
from book_guard import _pictos as p
from book_guard._constants import RANK_BOOK_GUARD
from book_guard._evening_lock import EveningLock, run_evening
from book_guard._state import snapshot
from book_guard.tests._evening_helpers import (
    ON_PACE_DAY,
    arm,
    fake_wait,
    no_grant,
    pay,
)
from book_guard.tests._flow_helpers import LOCKED_DAY, add_credit, make_snap
from book_guard.tests._flow_helpers_lock import FakeRoot, install_lock_fakes

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths

# (a) paid today: exit 0, no window ------------------------------------------


def test_paid_today_exits_zero_without_a_window(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    asked = fake_wait(monkeypatch, answers=False)
    pay(bg_paths, LOCKED_DAY)
    assert run_evening(bg_paths, production=True, today=LOCKED_DAY) == 0
    assert seen.events == []
    assert asked == []  # nothing to show, so no reason to wait for a display


# (b) the rung, not the pace --------------------------------------------------


def test_on_pace_but_unpaid_still_locks_past_every_stand_down(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    no_grant(monkeypatch)
    fake_wait(monkeypatch, answers=True)
    add_credit(bg_paths, "2026-10-02", 1000)  # far ahead: the normal gate is up
    assert snapshot(bg_paths, today=ON_PACE_DAY).locked is False

    def stood_down(*_a: object, **_k: object) -> str:
        msg = "evening mode must ignore the morning and lockdown stand-downs"
        raise AssertionError(msg)

    monkeypatch.setattr(_lock, "gate_hold", stood_down)
    monkeypatch.setattr(_night_lockdown, "gate_hold", stood_down)
    monkeypatch.setattr(_night_lockdown, "evening_lockdown_for", stood_down)
    assert run_evening(bg_paths, production=True, today=ON_PACE_DAY) == 0
    assert seen.events[-1] == "window.run"


def test_unreadable_ledger_counts_as_unpaid(
    bg_paths: Paths, caplog: pytest.LogCaptureFixture
) -> None:
    bg_paths.data_dir.mkdir(parents=True)
    bg_paths.ledger.write_text("{not json", encoding="utf-8")
    with caplog.at_level(logging.WARNING):
        assert _evening.reading_paid(bg_paths, LOCKED_DAY) is None
    assert "not valid JSON" in caplog.text


def test_unusable_key_is_logged_and_still_locks(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    seen = install_lock_fakes(monkeypatch)
    fake_wait(monkeypatch, answers=True)
    keyless = replace(bg_paths, key_file=bg_paths.data_dir / "no")
    assert run_evening(keyless, production=True, today=LOCKED_DAY) == 0
    assert "integrity key" in caplog.text
    assert seen.events[-1] == "window.run"


def test_unpaid_production_run_locks_at_rank_150(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    asked = fake_wait(monkeypatch, answers=True)
    assert run_evening(bg_paths, production=True, today=LOCKED_DAY) == 0
    assert asked == [{"timeout_s": 10.0}]
    assert _evening.RANK_EVENING == 150 > RANK_BOOK_GUARD
    assert seen.events[0].startswith("arbiter book_guard 150 ")
    assert seen.configs[0].rank == 150
    assert "LOCKED" in bg_paths.next_file.read_text(encoding="utf-8")


def test_demo_evening_run_skips_the_x_wait(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    asked = fake_wait(monkeypatch, answers=False)
    assert run_evening(bg_paths, production=False, today=LOCKED_DAY) == 0
    assert asked == []
    assert seen.events[-1] == "window.run"


# (e) no X --------------------------------------------------------------------


def test_no_x_within_the_bound_exits_3_without_a_window(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    seen = install_lock_fakes(monkeypatch)
    fake_wait(monkeypatch, answers=False)
    assert run_evening(bg_paths, production=True, today=LOCKED_DAY) == 3
    assert seen.events == []
    assert "no X server" in caplog.text


# (c) the credit lands while the window is up ----------------------------------


def test_bonus_row_landing_closes_the_window_and_exits_zero(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = arm(bg_paths, monkeypatch)
    assert isinstance(gate.root, FakeRoot)
    (watch,) = [cb for ms, cb in gate.root.scheduled if ms == 3000]
    watch()
    assert "window.close" not in seen.events  # first look: still unpaid
    pay(bg_paths, LOCKED_DAY)
    gate.root.scheduled.clear()
    watch()
    assert seen.events.count("window.close") == 1
    assert gate.exit_code == 0


def test_a_credit_noticed_by_the_refresh_closes_it_too(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = arm(bg_paths, monkeypatch)
    pay(bg_paths, LOCKED_DAY)
    gate._refresh()
    assert seen.events.count("window.close") == 1


def test_an_unpaid_refresh_keeps_the_window(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = arm(bg_paths, monkeypatch)
    add_credit(bg_paths, "2026-10-02", 1000)  # pace is fine; the rung is not
    gate._refresh()
    assert "window.close" not in seen.events


# (d) end evening -------------------------------------------------------------


def test_end_evening_closes_with_the_chain_exit_code(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = arm(bg_paths, monkeypatch)
    gate._end()
    assert gate.exit_code == _evening.EXIT_END_EVENING == 10
    assert seen.events.count("window.close") == 1


def test_run_returns_the_gate_exit_code(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    install_lock_fakes(monkeypatch)
    fake_wait(monkeypatch, answers=True)
    monkeypatch.setattr(EveningLock, "run", lambda self: self._end())
    assert run_evening(bg_paths, production=True, today=LOCKED_DAY) == 10


def test_every_surface_gets_the_end_control(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, _seen = arm(bg_paths, monkeypatch)
    controls: list[Any] = []
    monkeypatch.setattr(
        _evening_lock,
        "add_end_control",
        lambda parent, end: controls.append((parent, end)),
    )
    surface: Any = SimpleNamespace(output_name="DP-0", is_primary=True, index=0)
    a: Any = "a"
    b: Any = "b"
    gate.build_surface(a, surface)
    gate.build_surface(b, surface)
    assert controls == [("a", gate._end), ("b", gate._end)]


# what the window shows -------------------------------------------------------


def test_the_window_shows_the_evening_goal(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, _seen = arm(bg_paths, monkeypatch)
    view = gate._vars.view
    assert view is not None
    snap = snapshot(bg_paths, today=LOCKED_DAY)
    goal = view.gauges[0]
    assert (goal.icon, goal.value, goal.total) == (
        p.MOON,
        snap.pace.pages_today,
        snap.pace.ask.bonus_at,
    )
    assert not goal.done
    assert view.locked  # shown as locked even on an on-pace day


def test_the_goal_gauge_pairs_with_the_month_gauge_only() -> None:
    snap = make_snap(locked=False)
    view = _evening.evening_view(p.build(snap), snap)
    assert [g.icon for g in view.gauges] == [p.MOON, p.MONTH]
    assert view.locked
