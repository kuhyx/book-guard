# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The production gate waits for an X server before it builds any window.

2026-11-17: the unit started before the display answered, GateRoot() raised
TclError, and Restart=on-failure looped ~15,700 times. No X is a wait, never
a crash (leetcode-guard does the same, see its cmd_lock).
"""

from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _lock
from book_guard.tests._flow_helpers import LOCKED_DAY, add_credit
from book_guard.tests._flow_helpers_lock import FakeRoot, install_lock_fakes

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard._paths import Paths
    from book_guard.tests._flow_helpers_lock import LockFakes


class XDownError(Exception):
    """Stands in for a wait that never returns."""


def _trace_roots(monkeypatch: pytest.MonkeyPatch, seen: LockFakes) -> None:
    def root() -> FakeRoot:
        seen.events.append("GateRoot")
        return FakeRoot()

    monkeypatch.setattr(_lock, "GateRoot", root)


def _fake_wait(
    monkeypatch: pytest.MonkeyPatch,
    seen: LockFakes,
    during: Callable[[], None] = lambda: None,
) -> None:
    def wait(**_kwargs: Any) -> bool:
        seen.events.append("wait_for_x_server")
        during()
        return True

    monkeypatch.setattr(_lock, "wait_for_x_server", wait, raising=False)


def test_production_waits_for_x_before_building_the_window(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    _trace_roots(monkeypatch, seen)
    _fake_wait(monkeypatch, seen)
    assert _lock.run_gate(bg_paths, production=True, today=LOCKED_DAY) == 0
    assert seen.events.index("wait_for_x_server") < seen.events.index("GateRoot")


def test_no_window_is_built_while_x_is_down(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    _trace_roots(monkeypatch, seen)

    def blocked(**_kwargs: Any) -> bool:
        raise XDownError

    monkeypatch.setattr(_lock, "wait_for_x_server", blocked, raising=False)
    with pytest.raises(XDownError):
        _lock.run_gate(bg_paths, production=True, today=LOCKED_DAY)
    assert "GateRoot" not in seen.events


def test_the_decision_is_made_after_x_answers(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    _trace_roots(monkeypatch, seen)
    # Reading landed while the gate waited for the display: no lock any more.
    _fake_wait(monkeypatch, seen, lambda: add_credit(bg_paths, "2026-10-02", 1000))
    assert _lock.run_gate(bg_paths, production=True, today=date(2026, 10, 20)) == 0
    assert "GateRoot" not in seen.events


def test_demo_mode_never_waits_for_x(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    _fake_wait(monkeypatch, seen)
    assert _lock.run_gate(bg_paths, production=False, today=LOCKED_DAY) == 0
    assert "wait_for_x_server" not in seen.events
