# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The gate does not re-arm after tonight's evening night-lockdown.

The verdict rules (evening = today, >= 12:00; missing/garbage = no lockdown)
are tested once, in gatelock.night_lockdown; these check book-guard's wiring.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

from book_guard import _lock, _night_lockdown
from book_guard._night_lockdown import evening_lockdown_for
from book_guard._paths import Paths, _default
from book_guard.tests._flow_helpers import LOCKED_DAY
from book_guard.tests._flow_helpers_lock import install_lock_fakes

if TYPE_CHECKING:
    from pathlib import Path

    import pytest

NOW = datetime(2026, 10, 17, 22, 30).astimezone()


def _stamp(paths: Paths, when: str) -> None:
    """Write the sandbox stamp for a LOCAL wall-clock time."""
    epoch = int(datetime.fromisoformat(when).astimezone().timestamp())
    paths.night_lockdown.write_text(f"{epoch}\n", encoding="ascii")


def test_paths_carry_their_own_stamp(
    bg_paths: Paths, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    assert bg_paths.night_lockdown == tmp_path / "locked_at_epoch"
    monkeypatch.setenv("BOOK_GUARD_ROOT", str(tmp_path / "sandbox"))
    assert _default().night_lockdown == tmp_path / "sandbox" / "locked_at_epoch"
    monkeypatch.delenv("BOOK_GUARD_ROOT")
    assert str(_default().night_lockdown) == "/var/lib/night-lockdown/locked_at_epoch"


def test_missing_stamp_does_not_hold(bg_paths: Paths) -> None:
    assert evening_lockdown_for(bg_paths, NOW) is None


def test_tonights_evening_lockdown_holds(bg_paths: Paths) -> None:
    _stamp(bg_paths, "2026-10-17T21:05")
    assert evening_lockdown_for(bg_paths, NOW) == (
        "night lockdown already locked tonight at 21:05; no re-arm after it"
    )


def test_the_0401_morning_relock_does_not_hold(bg_paths: Paths) -> None:
    _stamp(bg_paths, "2026-10-17T04:01")
    assert evening_lockdown_for(bg_paths, NOW) is None


def test_yesterdays_evening_lockdown_does_not_hold(bg_paths: Paths) -> None:
    _stamp(bg_paths, "2026-10-16T21:05")
    assert evening_lockdown_for(bg_paths, NOW) is None


def test_garbage_stamp_does_not_hold(
    bg_paths: Paths, caplog: pytest.LogCaptureFixture
) -> None:
    bg_paths.night_lockdown.write_text("garbage", encoding="ascii")
    assert evening_lockdown_for(bg_paths, NOW) is None
    assert "not a unix epoch" in caplog.text


def test_tonights_lockdown_holds_the_gate(
    bg_paths: Paths,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    seen = install_lock_fakes(monkeypatch)
    monkeypatch.setattr(
        _night_lockdown,
        "evening_lockdown_for",
        lambda _paths: "night lockdown already locked tonight at 21:05",
    )
    assert _lock.run_gate(bg_paths, production=True, today=LOCKED_DAY) == 0
    assert seen.events == []
    assert "not locking yet" in caplog.text
    assert "locked tonight at 21:05" in caplog.text
    # Still behind pace, and the phone is told so: a deferral, not a pardon.
    assert "LOCKED" in bg_paths.next_file.read_text(encoding="utf-8")
    assert not bg_paths.ledger.exists()


def test_after_the_morning_relock_the_gate_still_locks(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = install_lock_fakes(monkeypatch)
    _stamp(bg_paths, f"{datetime.now(tz=UTC).astimezone():%Y-%m-%d}T04:01")
    assert _lock.run_gate(bg_paths, production=False, today=LOCKED_DAY) == 0
    assert seen.events[-1] == "window.run"
