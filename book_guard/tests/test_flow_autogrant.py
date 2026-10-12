# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A day that asks no pages gets its hour from the periodic run, once."""

from __future__ import annotations

from datetime import UTC, date, datetime
from typing import TYPE_CHECKING

from book_guard import _actions, _ledger
from book_guard._autogrant import AUTO_PREFIX, auto_grant
from book_guard._ledger import CREDIT, Entry
from book_guard._render import status_lines
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import add_credit

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths

TUE = date(2026, 10, 13)
NOON = datetime(2026, 10, 13, 10, 0, tzinfo=UTC).timestamp()


def _free_tue(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("freedays.is_free_day", lambda day=None, **_k: day == TUE)


def _credits(paths: Paths) -> list[Entry]:
    return _ledger.load(paths.ledger, paths.key_file).of_kind(CREDIT)


def test_a_free_day_is_granted_once(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _free_tue(monkeypatch)
    preview = auto_grant(bg_paths, today=TUE, now=NOON, dry_run=True)
    assert preview is not None
    assert _credits(bg_paths) == []
    grant = auto_grant(bg_paths, today=TUE, now=NOON)
    assert grant is not None
    assert (grant.entry_id, grant.day, grant.amount) == (
        AUTO_PREFIX + "2026-10-13",
        "2026-10-13",
        0,
    )
    assert grant.detail["bonus"] == "1"
    assert grant.detail["ended_at"] == str(int(NOON))
    assert auto_grant(bg_paths, today=TUE, now=NOON + 60) is None
    assert [e.entry_id for e in _credits(bg_paths)] == [grant.entry_id]
    snap = snapshot(bg_paths, today=TUE, is_free=lambda d: d == TUE)
    # No pages: the pace is untouched, the day shows its hour.
    assert (snap.pace.pages, snap.pace.ask.bonus) == (0, True)
    assert status_lines(snap)[3] == (
        "Today asks no pages: the +1h bonus is granted without reading"
    )


def test_a_weekday_surplus_cut_to_zero_is_granted(bg_paths: Paths) -> None:
    # 2000 pages on Monday empty every Mon-Fri day left in October.
    add_credit(bg_paths, "2026-10-12", 2000)
    grant = auto_grant(bg_paths, today=TUE, now=NOON)
    assert grant is not None
    assert grant.detail["ended_at"] == str(int(NOON))


def test_a_day_that_asks_pages_is_not_granted(bg_paths: Paths) -> None:
    assert auto_grant(bg_paths, today=TUE, now=NOON) is None
    assert _credits(bg_paths) == []


def test_a_day_with_a_bonus_already_is_not_granted(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _free_tue(monkeypatch)
    row = Entry("s", CREDIT, TUE.isoformat(), 20, {"bonus": "1"})
    _ledger.append(bg_paths.ledger, bg_paths.key_file, row)
    assert auto_grant(bg_paths, today=TUE, now=NOON) is None


def test_before_the_switch_nothing_is_granted(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("freedays.is_free_day", lambda *_a, **_k: True)
    assert auto_grant(bg_paths, today=date(2026, 10, 11), now=NOON) is None


def test_the_day_defaults_to_the_local_day_of_now(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _free_tue(monkeypatch)
    grant = auto_grant(bg_paths, now=NOON)
    assert grant is not None
    assert grant.day == "2026-10-13"


def test_the_inbox_pass_grants_and_logs(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    row = Entry(AUTO_PREFIX + "2026-10-13", CREDIT, "2026-10-13")
    monkeypatch.setattr(_actions, "auto_grant", lambda _p: row)
    caplog.set_level("INFO")
    _actions.process(bg_paths, settle_wait=False)
    assert "2026-10-13: today asks no pages, bonus granted" in caplog.text
