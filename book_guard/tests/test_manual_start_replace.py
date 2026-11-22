# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_manual_pages: a real photo of the start page replaces a manual start."""

from __future__ import annotations

from datetime import datetime, timedelta
import json
from typing import TYPE_CHECKING

import pytest

from book_guard import _manual_start
from book_guard._ledger import load
from book_guard._photos import MANUAL_START_NAME
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import T0, add_book, rec, seed_photos

if TYPE_CHECKING:
    from book_guard._paths import Paths

AT = T0 + timedelta(hours=2)
NOW = AT + timedelta(minutes=10)


def _seed(paths: Paths) -> None:
    """A finished p. 200-259 session that stopped at T0 + 1 h."""
    add_book(paths, pages=611)
    seed_photos(
        paths,
        rec("s", 200, T0),
        rec("e", 259, T0 + timedelta(hours=1)),
    )


_REAL_NOW = _manual_start._now


@pytest.fixture(autouse=True)
def _clock(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(_manual_start, "_now", lambda: NOW)


def _start(paths: Paths, page: int = 260, at: datetime = AT, reason: str = "r") -> str:
    return _manual_start.start(paths, page=page, at=at, reason=reason)


def test_a_later_photo_of_the_start_page_replaces_it(bg_paths: Paths) -> None:
    _seed(bg_paths)
    _start(bg_paths)
    base = [rec("s", 200, T0), rec("e", 259, T0 + timedelta(hours=1))]
    real = rec("real-start", 260, AT + timedelta(minutes=2))
    seed_photos(bg_paths, *base, real)
    ledger = load(bg_paths.ledger, bg_paths.key_file)
    records = {r.sha: r for r in [*base, real]}
    assert _manual_start.replaced_by(ledger, records, real.sha) is not None
    assert _manual_start.replaced_by(ledger, records, base[0].sha) is None
    start = snapshot(bg_paths).open_start
    assert start is not None
    assert start.sha == real.sha
    assert [p.name for p in _manual_start.pages(ledger, records)].count(
        MANUAL_START_NAME
    ) == 0


def test_a_different_page_does_not_replace_it(bg_paths: Paths) -> None:
    _seed(bg_paths)
    _start(bg_paths)
    ledger = load(bg_paths.ledger, bg_paths.key_file)
    base = [rec("s", 200, T0), rec("e", 259, T0 + timedelta(hours=1))]
    later = rec("later", 260, AT + timedelta(minutes=5))
    stop = rec("stop", 270, AT + timedelta(minutes=2))
    records = {r.sha: r for r in [*base, stop, later]}
    names = [p.name for p in _manual_start.pages(ledger, records)]
    assert MANUAL_START_NAME in names


def test_inbox_logs_the_replacement_once(bg_paths: Paths) -> None:
    _seed(bg_paths)
    _start(bg_paths)
    base = [rec("s", 200, T0), rec("e", 259, T0 + timedelta(hours=1))]
    real = rec("real-start", 260, AT + timedelta(minutes=2))
    records = {r.sha: r for r in [*base, real]}
    ledger = load(bg_paths.ledger, bg_paths.key_file)
    _manual_start.log_replacement(bg_paths, ledger, records, real)
    _manual_start.log_replacement(bg_paths, ledger, records, base[0])
    lines = [
        json.loads(line)
        for line in bg_paths.error_log.read_text(encoding="utf-8").splitlines()
    ]
    hits = [e for e in lines if e.get("error") == "manual start replaced"]
    assert len(hits) == 1
    assert hits[0]["photo"] == real.sha
