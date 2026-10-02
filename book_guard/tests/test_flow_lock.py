# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""BookGuardLock and run_gate, with gatelock and the Tk view faked out."""

from __future__ import annotations

from dataclasses import replace
from datetime import date
from types import SimpleNamespace
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _lock
from book_guard._claude import ClaudeUnavailableError
from book_guard._constants import POLL_INTERVAL_MS, RANK_BOOK_GUARD
from book_guard._quiz import Verdict
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import (
    LOCKED_DAY,
    add_credit,
    quiz_pair,
    seed_photos,
)
from book_guard.tests._flow_helpers_lock import FakeJob, FakeRoot, install_lock_fakes

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard.tests._flow_helpers_lock import LockFakes


PARENT: Any = object()
"""Stands in for the Tk parent; the faked view builders never touch it."""


def _surface(name: str = "DP-0", *, primary: bool = True, index: int = 0) -> Any:
    return SimpleNamespace(output_name=name, is_primary=primary, index=index)


def _arm(
    paths: Paths, monkeypatch: pytest.MonkeyPatch, *, production: bool = False
) -> tuple[_lock.BookGuardLock, LockFakes]:
    seen = install_lock_fakes(monkeypatch)
    snap = snapshot(paths, today=LOCKED_DAY)
    return _lock.BookGuardLock(paths, snap, production=production), seen


def _root(gate: _lock.BookGuardLock) -> FakeRoot:
    assert isinstance(gate.root, FakeRoot)
    return gate.root


def _job(gate: _lock.BookGuardLock) -> FakeJob:
    assert isinstance(gate._worker, FakeJob)
    return gate._worker


def test_demo_lock_arms_without_waiting(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = _arm(bg_paths, monkeypatch)
    assert _root(gate).titles == ["Book Guard [DEMO]"]
    assert seen.events == [
        (
            f"arbiter book_guard {RANK_BOOK_GUARD} "
            "[('disable_vt', False), ('grab', 'local')]"
        ),
        "publish",
        "acquire",
        "window.setup",
        "window.grab_input",
    ]
    assert [ms for ms, _cb in _root(gate).scheduled] == [POLL_INTERVAL_MS, 500]
    assert gate._vars.status.get().startswith("LOCKED: 136 pages behind")
    assert gate._vars.todo.get().startswith("No book registered")
    assert gate._vars.quiz_title.get() == "No session is waiting for a summary."
    gate.run()
    assert seen.events[-1] == "window.run"


def test_production_lock_waits_for_its_turn(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = _arm(bg_paths, monkeypatch, production=True)
    assert _root(gate).titles == ["Book Guard"]
    assert seen.events[1:4] == ["publish", "wait_for_turn", "acquire"]
    assert seen.configs[0].resolved_grab() == "global"
    gate.build_surface(PARENT, _surface())
    assert seen.demo_closes == []


def test_render_names_the_waiting_session(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seed_photos(bg_paths, *quiz_pair())
    gate, _seen = _arm(bg_paths, monkeypatch)
    assert gate._vars.quiz_title.get() == "Summary for p. 10-11 (3-5 sentences):"
    assert gate._vars.todo.get().startswith("WRITE A SUMMARY")


def test_empty_todo_gets_a_nudge(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(_lock, "todo_lines", lambda _snap: [])
    gate, _seen = _arm(bg_paths, monkeypatch)
    assert gate._vars.todo.get() == "Go read, then upload photos."


def test_surfaces_and_focus(bg_paths: Paths, monkeypatch: pytest.MonkeyPatch) -> None:
    gate, seen = _arm(bg_paths, monkeypatch)
    gate.build_surface(PARENT, _surface("DP-0", primary=True, index=1))
    gate.build_surface(PARENT, _surface("HDMI-0", primary=False, index=0))
    gate.build_surface(PARENT, _surface("DP-2", primary=False, index=2))
    assert sorted(gate._inputs) == ["DP-0", "HDMI-0"]
    assert seen.demo_closes == [gate.close] * 3

    gate.on_focus_ready(None)
    gate.on_focus_ready(_surface("DP-2"))
    gate.on_focus_ready(_surface("DP-0"))
    assert [i.summary.focused for i in seen.inputs] == [1, 0]

    gate.teardown_surface(_surface("DP-0"))
    gate.teardown_surface(_surface("never-built"))
    assert list(gate._inputs) == ["HDMI-0"]


def test_callback_error_and_close_hooks(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    gate, seen = _arm(bg_paths, monkeypatch)

    def fail() -> None:
        msg = "boom"
        raise ValueError(msg)

    def tk_callback() -> None:
        """Like Tk's handler: on_callback_error runs while the error is live."""
        try:
            fail()
        except ValueError:
            gate.on_callback_error()
            raise

    with pytest.raises(ValueError, match="boom"):
        tk_callback()
    assert "ValueError: boom" in caplog.text
    assert gate._vars.feedback.get() == "Something went wrong -- still watching."
    gate.on_close()
    assert _job(gate).shut
    gate.close()
    gate.close()
    assert seen.events.count("window.close") == 1


def test_ignore_completion() -> None:
    _lock._ignore(object())  # accepts anything, returns nothing


# -- run_gate -----------------------------------------------------------------


def test_run_gate_refuses_without_a_key(
    bg_paths: Paths, caplog: pytest.LogCaptureFixture
) -> None:
    keyless = replace(bg_paths, key_file=bg_paths.data_dir / "no")
    assert _lock.run_gate(keyless, production=True, today=LOCKED_DAY) == 0
    assert "gate not armed" in caplog.text
    assert not keyless.next_file.exists()


def test_run_gate_on_pace_does_not_lock(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    add_credit(bg_paths, "2026-10-02", 300)
    assert _lock.run_gate(bg_paths, production=False, today=date(2026, 10, 20)) == 0
    assert bg_paths.next_file.exists()
    assert seen.events == []


def test_run_gate_behind_locks_and_runs(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    assert _lock.run_gate(bg_paths, production=False, today=LOCKED_DAY) == 0
    assert "LOCKED" in bg_paths.next_file.read_text(encoding="utf-8")
    assert seen.events[-1] == "window.run"


def test_submit_work_runs_the_grader(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seed_photos(bg_paths, *quiz_pair())
    gate, seen = _arm(bg_paths, monkeypatch)
    gate.build_surface(PARENT, _surface())
    seen.inputs[0].summary.set("I read it all.")
    graded: list[str] = []

    def quiz_one(_paths: Paths, _view: object, text: str) -> Verdict:
        graded.append(text)
        return Verdict(passed=True, feedback="")

    monkeypatch.setattr(_lock, "quiz_one", quiz_one)
    gate._submit()
    work, _done = _job(gate).started[-1]
    assert work() == Verdict(passed=True, feedback="")
    assert graded == ["I read it all."]


def test_tick_reports_errors_and_refreshes(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, _seen = _arm(bg_paths, monkeypatch)
    _job(gate).finish = ClaudeUnavailableError("offline")
    gate._tick()
    assert gate._vars.feedback.get() == "Could not finish: offline"
    assert bg_paths.next_file.exists()
