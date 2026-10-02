# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The morning-session carrot: the gate holds until wake-alarm's signed instant.

The verdict rules themselves (signed, today, not expired, the boot retry) are
tested once, in gatelock.morning_session; these check book-guard's wiring.
"""

from __future__ import annotations

from datetime import UTC, datetime
import json
from typing import TYPE_CHECKING

from gatelock.log_integrity import compute_entry_hmac
import pytest

from book_guard import _lock, _morning
from book_guard._morning import morning_skip_for
from book_guard.tests._flow_helpers import LOCKED_DAY
from book_guard.tests._flow_helpers_lock import install_lock_fakes

if TYPE_CHECKING:
    from book_guard._paths import Paths


@pytest.fixture(autouse=True)
def _signing_key(bg_paths: Paths, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "gatelock.log_integrity.DEFAULT_HMAC_KEY_FILE", bg_paths.key_file
    )


def _sign_morning(paths: Paths, *, until: str = "23:59", sign: bool = True) -> None:
    """Write today's morning, earned until ``until`` (local), into the sandbox."""
    today = datetime.now(tz=UTC).astimezone().date().isoformat()
    entry: dict[str, object] = {
        "date": today,
        "outcome": "completed",
        "exempt_until": datetime.fromisoformat(f"{today}T{until}")
        .astimezone()
        .isoformat(),
    }
    if sign:
        entry["hmac"] = compute_entry_hmac(entry)
    paths.morning_session.write_text(json.dumps(entry), encoding="utf-8")


def test_reads_the_paths_own_file(bg_paths: Paths) -> None:
    assert morning_skip_for(bg_paths, wait=False) is None
    _sign_morning(bg_paths)
    skip = morning_skip_for(bg_paths, wait=False)
    assert skip is not None
    assert str(skip) == "completed session, no lock until 23:59"


def test_the_retry_budget_is_book_guards_own(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    naps: list[float] = []
    assert morning_skip_for(bg_paths, wait=True, sleep=naps.append) is None
    assert naps == []
    monkeypatch.setattr(_morning, "MORNING_RETRY_SECONDS", 10.0)
    monkeypatch.setattr("gatelock.morning_session.MORNING_WINDOW", ((0, 0), (23, 59)))
    assert morning_skip_for(bg_paths, wait=True, sleep=naps.append) is None
    assert naps


def test_a_live_carrot_holds_the_gate(
    bg_paths: Paths,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    seen = install_lock_fakes(monkeypatch)
    _sign_morning(bg_paths)
    assert _lock.run_gate(bg_paths, production=True, today=LOCKED_DAY) == 0
    assert seen.events == []
    assert "not locking yet" in caplog.text
    assert "no lock until 23:59" in caplog.text
    # Still behind pace, and the phone is told so: a deferral, not a pardon.
    assert "LOCKED" in bg_paths.next_file.read_text(encoding="utf-8")
    assert not bg_paths.ledger.exists()


@pytest.mark.parametrize(
    ("until", "sign"), [("00:00", True), ("23:59", False)], ids=["expired", "forged"]
)
def test_an_expired_or_forged_carrot_locks(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, until: str, *, sign: bool
) -> None:
    seen = install_lock_fakes(monkeypatch)
    _sign_morning(bg_paths, until=until, sign=sign)
    assert _lock.run_gate(bg_paths, production=False, today=LOCKED_DAY) == 0
    assert seen.events[-1] == "window.run"
