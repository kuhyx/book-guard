# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_phone_logs: the app's uploaded log entries, events and bug reports."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

from book_guard import _phone_logs

if TYPE_CHECKING:
    from book_guard._paths import Paths


def _lines(paths: Paths) -> list[dict[str, object]]:
    return [
        json.loads(line)
        for line in paths.error_log.read_text(encoding="utf-8").splitlines()
    ]


def test_merge_phone(bg_paths: Paths) -> None:
    assert _phone_logs.merge_phone(bg_paths) == 0
    bg_paths.phone_logs.mkdir(parents=True)
    (bg_paths.phone_logs / "a.json").write_text(
        '{"stage": "reader", "error": "unreadable", "host": "desktop"}',
        encoding="utf-8",
    )
    (bg_paths.phone_logs / "b.json").write_text('{"stage": "x"}', encoding="utf-8")
    (bg_paths.phone_logs / "c.json").write_text("[1]", encoding="utf-8")
    (bg_paths.phone_logs / "d.json").write_text("not json", encoding="utf-8")
    assert _phone_logs.merge_phone(bg_paths) == 2
    first, second = _lines(bg_paths)
    assert first["host"] == "desktop"  # the sender's own label is kept
    assert second["host"] == "phone"
    assert list(bg_paths.phone_logs.iterdir()) == []


def test_merge_phone_routes_lifecycle_events(bg_paths: Paths) -> None:
    # The app's photo pipeline steps (camera, captured, queued, uploaded...)
    # go to their own file: the error log stays errors only.
    bg_paths.phone_logs.mkdir(parents=True)
    (bg_paths.phone_logs / "a.json").write_text(
        '{"level": "event", "stage": "photo", "event": "captured", "attempt": "a1"}',
        encoding="utf-8",
    )
    (bg_paths.phone_logs / "b.json").write_text(
        '{"stage": "photo", "error": "boom"}', encoding="utf-8"
    )
    assert _phone_logs.merge_phone(bg_paths) == 2
    assert [e["error"] for e in _lines(bg_paths)] == ["boom"]
    (event,) = [
        json.loads(line)
        for line in bg_paths.phone_events.read_text(encoding="utf-8").splitlines()
    ]
    assert (event["event"], event["attempt"], event["host"]) == (
        "captured",
        "a1",
        "phone",
    )
    assert bg_paths.phone_events.parent == bg_paths.error_log.parent


def test_merge_reports(bg_paths: Paths) -> None:
    assert _phone_logs.merge_reports(bg_paths) == 0
    folder = bg_paths.uploaded_reports
    folder.mkdir(parents=True)
    (folder / "r1.jpg").write_bytes(b"jpeg")
    (folder / "r1.json").write_text(
        '{"photo": "start_a.jpg", "failure": "no page number found", "actual_page": 7}',
        encoding="utf-8",
    )
    (folder / "r2.json").write_text("[]", encoding="utf-8")  # no image, not a dict
    (folder / "r3.json").write_text("{bad", encoding="utf-8")
    assert _phone_logs.merge_reports(bg_paths) == 2
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
