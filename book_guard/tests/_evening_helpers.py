# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Shared setup for the evening-mode tests."""

from __future__ import annotations

from datetime import date, datetime, time
from typing import TYPE_CHECKING, Any

from book_guard import _evening_lock, _ledger
from book_guard._evening_lock import EveningLock
from book_guard._ledger import CREDIT, Entry
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import LOCKED_DAY
from book_guard.tests._flow_helpers_lock import install_lock_fakes

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths
    from book_guard.tests._flow_helpers_lock import LockFakes

ON_PACE_DAY = date(2026, 10, 20)


def pay(paths: Paths, day: date) -> None:
    """The row the reading rung is: bonus flag, ended today, signed."""
    noon = datetime.combine(day, time(12)).astimezone().timestamp()
    detail = {"bonus": "1", "ended_at": str(int(noon)), "pages": "30"}
    row = Entry(f"credit:{day}:bonus", CREDIT, day.isoformat(), 30, detail)
    _ledger.append(paths.ledger, paths.key_file, row)


def no_grant(monkeypatch: pytest.MonkeyPatch) -> None:
    """A day that asks pages: nothing grants the hour for free."""
    monkeypatch.setattr(_evening_lock, "auto_grant", lambda *_a, **_k: None)


def arm(
    paths: Paths, monkeypatch: pytest.MonkeyPatch, day: date = LOCKED_DAY
) -> tuple[EveningLock, LockFakes]:
    seen = install_lock_fakes(monkeypatch)
    snap = snapshot(paths, today=day)
    return EveningLock(paths, snap, production=True, today=day), seen


def fake_wait(monkeypatch: pytest.MonkeyPatch, *, answers: bool) -> list[Any]:
    asked: list[Any] = []

    def wait(**kwargs: Any) -> bool:
        asked.append(kwargs)
        return answers

    monkeypatch.setattr(_evening_lock, "wait_for_x_server", wait)
    return asked
