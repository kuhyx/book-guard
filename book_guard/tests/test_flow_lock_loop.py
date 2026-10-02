# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The lock's loop: tick, refresh, poll, submit, escape -- no threads, no Tk."""

from __future__ import annotations

from types import SimpleNamespace
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _lock
from book_guard._constants import POLL_INTERVAL_MS
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


def _arm(
    paths: Paths, monkeypatch: pytest.MonkeyPatch, *, forms: int = 1
) -> tuple[_lock.BookGuardLock, LockFakes]:
    seen = install_lock_fakes(monkeypatch)
    gate = _lock.BookGuardLock(
        paths, snapshot(paths, today=LOCKED_DAY), production=False
    )
    for i in range(forms):
        gate.build_surface(
            PARENT, SimpleNamespace(output_name=f"out{i}", is_primary=True, index=i)
        )
    return gate, seen


def _job(gate: _lock.BookGuardLock) -> FakeJob:
    assert isinstance(gate._worker, FakeJob)
    return gate._worker


def _scheduled(gate: _lock.BookGuardLock) -> list[int]:
    assert isinstance(gate.root, FakeRoot)
    return [ms for ms, _cb in gate.root.scheduled]


def test_tick_idle_just_reschedules(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, _seen = _arm(bg_paths, monkeypatch)
    gate._tick()
    assert _scheduled(gate)[-1] == 500
    assert not bg_paths.next_file.exists()  # no refresh without a finished job


def test_tick_after_a_job_refreshes_and_stays_locked(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = _arm(bg_paths, monkeypatch)
    _job(gate).finish = True
    gate._tick()
    assert bg_paths.next_file.exists()
    assert "window.close" not in seen.events
    assert gate._snap.today == LOCKED_DAY


def test_refresh_releases_once_on_pace(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = _arm(bg_paths, monkeypatch)
    add_credit(bg_paths, "2026-10-03", 1000)
    _job(gate).finish = True
    before = len(_scheduled(gate))
    gate._tick()
    assert seen.events.count("window.close") == 1
    assert len(_scheduled(gate)) == before  # closed: no further tick
    gate._poll()
    assert len(_scheduled(gate)) == before  # nor a further poll


def test_poll_starts_a_quiet_inbox_pass(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, _seen = _arm(bg_paths, monkeypatch)
    calls: list[dict[str, Any]] = []
    monkeypatch.setattr(_lock, "process", lambda _paths, **kwargs: calls.append(kwargs))
    gate._poll()
    assert _scheduled(gate)[-1] == POLL_INTERVAL_MS
    work, done = _job(gate).started[-1]
    work()
    assert calls == [{"settle_wait": False}]
    assert done is _lock._ignore


def test_typed_takes_the_first_filled_form(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = _arm(bg_paths, monkeypatch, forms=2)
    assert gate._typed("summary") == ""
    seen.inputs[1].summary.set("  second form  ")
    seen.inputs[1].escape.set(" phrase ")
    assert gate._typed("summary") == "second form"
    assert gate._typed("escape") == "phrase"


def test_submit_needs_a_session_and_text(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = _arm(bg_paths, monkeypatch)
    seen.inputs[0].summary.set("text but no session")
    gate._submit()
    assert _job(gate).started == []

    seed_photos(bg_paths, *quiz_pair())
    gate, seen = _arm(bg_paths, monkeypatch)
    gate._submit()  # a session, but nothing typed
    assert _job(gate).started == []


def test_submit_while_busy(bg_paths: Paths, monkeypatch: pytest.MonkeyPatch) -> None:
    seed_photos(bg_paths, *quiz_pair())
    gate, seen = _arm(bg_paths, monkeypatch)
    seen.inputs[0].summary.set("my summary")
    _job(gate).busy = True
    gate._submit()
    assert gate._vars.feedback.get() == (
        "Busy reading new photos -- submit again in a moment."
    )
    assert _job(gate).started == []


@pytest.mark.parametrize(
    ("verdict", "shown"),
    [
        (Verdict(passed=True, feedback="Well read."), "Passed. Well read."),
        (Verdict(passed=False, feedback="Too vague."), "Not counted. Too vague."),
    ],
)
def test_submit_grades_and_clears(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, verdict: Verdict, shown: str
) -> None:
    seed_photos(bg_paths, *quiz_pair())
    gate, seen = _arm(bg_paths, monkeypatch, forms=2)
    seen.inputs[0].summary.set("my summary")
    gate._submit()
    assert gate._vars.feedback.get() == "Grading..."
    _work, done = _job(gate).started[-1]
    done(verdict)
    assert gate._vars.feedback.get() == shown
    assert [i.summary.get() for i in seen.inputs] == ["", ""]


def test_escape_error_is_shown(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, seen = _arm(bg_paths, monkeypatch)
    seen.inputs[0].escape.set("please")
    typed: list[str] = []

    def escape_today(_paths: Paths, text: str) -> str:
        typed.append(text)
        return "Type exactly"

    monkeypatch.setattr(_lock, "escape_today", escape_today)
    gate._escape()
    assert typed == ["please"]
    assert gate._vars.feedback.get() == "Type exactly"
    assert not bg_paths.next_file.exists()


def test_escape_success_refreshes(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    gate, _seen = _arm(bg_paths, monkeypatch)
    monkeypatch.setattr(_lock, "escape_today", lambda _p, _text: None)
    gate._escape()
    assert bg_paths.next_file.exists()
