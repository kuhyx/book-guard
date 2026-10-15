# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Book files in the share's ``books/`` folder, for the index tests."""

from __future__ import annotations

from typing import TYPE_CHECKING

from book_guard.tests._flow_helpers import LONG_TEXT

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths


def drop(paths: Paths, name: str = "war.txt", text: str = LONG_TEXT) -> Path:
    paths.books.mkdir(parents=True, exist_ok=True)
    path = paths.books / name
    path.write_text(text, encoding="utf-8")
    return path


def fail(paths: Paths, name: str = "bad.epub") -> Path:
    failed = paths.books / "failed"
    failed.mkdir(parents=True, exist_ok=True)
    (failed / f"{name}.txt").write_text("why\n", encoding="utf-8")
    path = failed / name
    path.write_bytes(b"x")
    return path
