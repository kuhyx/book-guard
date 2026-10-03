# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The inbox and the reader: sidecar notes in, reasons logged out."""

from __future__ import annotations

from datetime import timedelta
import json
import os
from typing import TYPE_CHECKING

from book_guard import _inbox
from book_guard._pagenum import Context
from book_guard._photo import PhotoFile
from book_guard._photo_context import sidecar_path
from book_guard._photos import REJECTED
from book_guard._vision import OTHER, PAGE, Reading
from book_guard.tests._flow_helpers import T0, sha

if TYPE_CHECKING:
    from pathlib import Path

    import pytest

    from book_guard._pagenum import Box
    from book_guard._paths import Paths

UPLOADED = T0 + timedelta(minutes=30)
NOW = UPLOADED.timestamp() + 60


def _drop(paths: Paths, name: str) -> Path:
    paths.inbox.mkdir(parents=True, exist_ok=True)
    path = paths.inbox / name
    path.write_bytes(name.encode())
    os.utime(path, (UPLOADED.timestamp(), UPLOADED.timestamp()))
    return path


def _fake_open(monkeypatch: pytest.MonkeyPatch, name: str) -> None:
    photo = PhotoFile(sha=sha(name), taken_at=T0, jpeg_b64=name)
    monkeypatch.setattr(_inbox, "open_photo", lambda _path: photo)


def test_sidecar_box_and_hint_reach_the_reader(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    photo = _drop(bg_paths, "check19_a.jpg")
    note = sidecar_path(photo)
    note.write_text('{"page": 19, "box": [1, 2, 30, 40]}', encoding="utf-8")
    _fake_open(monkeypatch, "check19_a.jpg")
    seen: list[tuple[Context, Box | None]] = []
    turns: list[int] = []
    monkeypatch.setattr(
        _inbox, "make_thumb", lambda _filed, _thumbs, turn: turns.append(turn)
    )

    def reader(_path: Path, context: Context, box: Box | None) -> Reading:
        seen.append((context, box))
        return Reading(PAGE, 19, None, "words", rotation=90)

    (record,) = _inbox.process_inbox(bg_paths, reader=reader, now=NOW).read
    assert seen == [(Context(expected=19, hint=19), (1, 2, 30, 40))]
    assert record.page == 19
    assert turns == [90]  # the thumbnail is turned as the page was read
    assert not note.exists()


def test_reader_reason_rejects_and_is_logged(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "start_a.jpg")
    _fake_open(monkeypatch, "start_a.jpg")

    def unclear(_path: Path, _context: Context, _box: Box | None) -> Reading:
        return Reading(
            OTHER, None, None, "text", reason="page number unclear (3 or 51)"
        )

    (record,) = _inbox.process_inbox(bg_paths, reader=unclear, now=NOW).read
    assert (record.status, record.reason) == (REJECTED, "page number unclear (3 or 51)")
    (line,) = bg_paths.error_log.read_text(encoding="utf-8").splitlines()
    entry = json.loads(line)
    assert (entry["stage"], entry["photo"], entry["error"]) == (
        "photo",
        "start_a.jpg",
        "page number unclear (3 or 51)",
    )
