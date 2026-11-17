# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""book-guard's error reporting: installed once by the CLI, into the spool."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING
from unittest.mock import MagicMock

from book_guard import _cli, _error_report, _lock
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import LOCKED_DAY
from book_guard.tests._flow_helpers_lock import install_lock_fakes

if TYPE_CHECKING:
    from pathlib import Path

    import pytest

    from book_guard._paths import Paths


def test_install_keeps_the_reporter_and_writes_the_spool(tmp_path: Path) -> None:
    """The CLI's install names this app and its repo in every report."""
    rep = _error_report.install()
    assert rep.app == "book-guard"
    rep.report("uncaught.python", ValueError("deliberate"))
    assert _error_report.SLOT.reporter is rep
    line = (tmp_path / "app-errors-spool" / "book-guard.jsonl").read_text()
    entry = json.loads(line)
    assert entry["repo"] == "kuhyx/book-guard"
    assert entry["error"] == "ValueError: deliberate"


def test_cli_main_installs_the_reporter(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every CLI run hooks its errors before the command runs."""
    seen: list[object] = []
    monkeypatch.setattr(_cli, "_parser", lambda: _FakeParser(seen))
    assert _cli.main([]) == 0
    assert seen == [_error_report.SLOT.reporter]
    assert seen[0] is not None


class _FakeParser:
    def __init__(self, seen: list[object]) -> None:
        self._seen = seen

    def parse_args(self, _argv: object) -> object:
        def handler(_args: object) -> int:
            self._seen.append(_error_report.SLOT.reporter)
            return 0

        return type("Args", (), {"handler": staticmethod(handler)})()


def test_lock_window_watches_stalls_once_installed(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A lock window built after install reports its own freezes."""
    install_lock_fakes(monkeypatch)
    watch = MagicMock()
    monkeypatch.setattr(_lock, "watch_stalls", watch)
    monkeypatch.setattr(_error_report.SLOT, "reporter", MagicMock())
    gate = _lock.BookGuardLock(
        bg_paths, snapshot(bg_paths, today=LOCKED_DAY), production=False
    )
    watch.assert_called_once_with(gate.root, _error_report.SLOT.reporter)


def test_lock_window_without_reporter_watches_nothing(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    """No reporter installed (a library caller): no stall watch."""
    install_lock_fakes(monkeypatch)
    watch = MagicMock()
    monkeypatch.setattr(_lock, "watch_stalls", watch)
    _lock.BookGuardLock(
        bg_paths, snapshot(bg_paths, today=LOCKED_DAY), production=False
    )
    watch.assert_not_called()
