# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_errlog: the shared failure log and Claude outages."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

from book_guard import _errlog

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths


def _lines(paths: Paths) -> list[dict[str, object]]:
    return [
        json.loads(line)
        for line in paths.error_log.read_text(encoding="utf-8").splitlines()
    ]


def test_log_error_appends_json_lines(bg_paths: Paths) -> None:
    _errlog.log_error(bg_paths, "photo", "no page number found", photo="a.jpg")
    _errlog.log_error(bg_paths, "request", "bad")
    first, second = _lines(bg_paths)
    assert (first["stage"], first["photo"], first["host"]) == ("photo", "a.jpg", "pc")
    assert second["error"] == "bad"


def test_log_error_never_raises(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    def broken(*_a: object) -> None:
        raise OSError

    monkeypatch.setattr(_errlog, "append_entry", broken)
    _errlog.log_error(bg_paths, "x", "y")  # logged as a warning only


def test_outage_marker(bg_paths: Paths, monkeypatch: pytest.MonkeyPatch) -> None:
    assert _errlog.claude_down_since(bg_paths) is None
    _errlog.claude_failed(bg_paths, "exited 1: usage limit")
    since = _errlog.claude_down_since(bg_paths)
    assert since is not None
    _errlog.claude_failed(bg_paths, "again")  # first failure wins
    assert _errlog.claude_down_since(bg_paths) == since
    assert len(_lines(bg_paths)) == 2
    _errlog.claude_ok(bg_paths)
    assert _errlog.claude_down_since(bg_paths) is None
    bg_paths.claude_down.write_text('{"since": 5}', encoding="utf-8")
    assert _errlog.claude_down_since(bg_paths) is None
    bg_paths.claude_down.write_text("[]", encoding="utf-8")
    assert _errlog.claude_down_since(bg_paths) is None
    bg_paths.claude_down.write_text("{cut sh", encoding="utf-8")
    assert _errlog.claude_down_since(bg_paths) is None
    bg_paths.claude_down.unlink()

    def unwritable(*_a: object, **_k: object) -> None:
        raise OSError

    monkeypatch.setattr(_errlog, "write_json", unwritable)
    _errlog.claude_failed(bg_paths, "disk full")  # logged, marker skipped
    assert _errlog.claude_down_since(bg_paths) is None
