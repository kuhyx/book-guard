# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_errlog: the shared failure log, phone entries, bug reports, outages."""

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

    monkeypatch.setattr(_errlog, "_append", broken)
    _errlog.log_error(bg_paths, "x", "y")  # logged as a warning only


def test_merge_phone(bg_paths: Paths) -> None:
    assert _errlog.merge_phone(bg_paths) == 0
    bg_paths.phone_logs.mkdir(parents=True)
    (bg_paths.phone_logs / "a.json").write_text(
        '{"stage": "reader", "error": "unreadable", "host": "desktop"}',
        encoding="utf-8",
    )
    (bg_paths.phone_logs / "b.json").write_text('{"stage": "x"}', encoding="utf-8")
    (bg_paths.phone_logs / "c.json").write_text("[1]", encoding="utf-8")
    (bg_paths.phone_logs / "d.json").write_text("not json", encoding="utf-8")
    assert _errlog.merge_phone(bg_paths) == 2
    first, second = _lines(bg_paths)
    assert first["host"] == "desktop"  # the sender's own label is kept
    assert second["host"] == "phone"
    assert list(bg_paths.phone_logs.iterdir()) == []


def test_merge_reports(bg_paths: Paths) -> None:
    assert _errlog.merge_reports(bg_paths) == 0
    folder = bg_paths.uploaded_reports
    folder.mkdir(parents=True)
    (folder / "r1.jpg").write_bytes(b"jpeg")
    (folder / "r1.json").write_text(
        '{"photo": "start_a.jpg", "failure": "no page number found", "actual_page": 7}',
        encoding="utf-8",
    )
    (folder / "r2.json").write_text("[]", encoding="utf-8")  # no image, not a dict
    (folder / "r3.json").write_text("{bad", encoding="utf-8")
    assert _errlog.merge_reports(bg_paths) == 2
    assert sorted(p.name for p in bg_paths.reports.iterdir()) == [
        "r1.jpg",
        "r1.json",
        "r2.json",
    ]
    first, second = _lines(bg_paths)
    assert (first["stage"], first["error"], first["actual_page"]) == (
        "bug-report",
        "no page number found",
        7,
    )
    assert str(first["report"]).endswith("r1.json")
    assert second["error"] == "reported by the reader"
    assert list(folder.iterdir()) == []


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
