# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Attaching ebook files: from the CLI and dropped into Reading/books."""

from __future__ import annotations

from pathlib import PosixPath
from typing import TYPE_CHECKING, NoReturn

import pytest

from book_guard import _attach
from book_guard._bookindex import index_path, load
from book_guard._booktext import BookTextError
from book_guard.tests._flow_helpers import ISBN13, LONG_TEXT, add_book

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths


def _book_file(where: Path, name: str = "war.txt", text: str = LONG_TEXT) -> Path:
    where.mkdir(parents=True, exist_ok=True)
    path = where / name
    path.write_text(text, encoding="utf-8")
    return path


def test_attach_without_a_book_refuses(bg_paths: Paths, tmp_path: Path) -> None:
    with pytest.raises(BookTextError, match="register the book first"):
        _attach.attach(bg_paths, _book_file(tmp_path / "src"))


def test_attach_to_the_current_book(bg_paths: Paths, tmp_path: Path) -> None:
    add_book(bg_paths)
    message = _attach.attach(bg_paths, _book_file(tmp_path / "src", "War.TXT"))
    assert message.startswith("Attached War.TXT: ")
    assert message.endswith("passages indexed")
    stored = bg_paths.data_dir / "books" / f"{ISBN13}.txt"
    assert stored.read_text(encoding="utf-8") == LONG_TEXT
    index = load(bg_paths, ISBN13)
    assert index is not None
    assert index.source == "War.TXT"


def test_attach_to_an_explicit_isbn_from_its_stored_copy(bg_paths: Paths) -> None:
    """A file already at its stored location is indexed without a copy."""
    stored = _book_file(bg_paths.data_dir / "books", "123.txt")
    _attach.attach(bg_paths, stored, isbn="123")
    assert stored.read_text(encoding="utf-8") == LONG_TEXT
    assert index_path(bg_paths, "123").exists()


def test_nothing_dropped(bg_paths: Paths) -> None:
    assert _attach.attach_dropped(bg_paths) == []


def test_dropped_files_done_failed_and_skipped(bg_paths: Paths, tmp_path: Path) -> None:
    add_book(bg_paths)
    folder = bg_paths.books
    good = _book_file(folder, "b-good.txt")
    short = _book_file(folder, "a-short.md", "too short")
    photo = _book_file(folder, "cover.jpg", "jpeg bytes")
    (folder / "subdir").mkdir()
    outside = _book_file(tmp_path / "elsewhere", "secret.txt")
    (folder / "escape.txt").symlink_to(outside)

    messages = _attach.attach_dropped(bg_paths)

    assert len(messages) == 2
    assert messages[0].startswith("a-short.md: only ")
    assert messages[1].startswith("Attached b-good.txt: ")
    assert (folder / "done" / "b-good.txt").exists()
    assert not good.exists()
    assert (folder / "failed" / "a-short.md").exists()
    assert not short.exists()
    reason = (folder / "failed" / "a-short.md.txt").read_text(encoding="utf-8")
    assert reason == messages[0] + "\n"
    assert photo.exists()
    assert (folder / "escape.txt").is_symlink()
    assert outside.exists()
    assert _attach.attach_dropped(bg_paths) == []  # moved files are not redone


def test_inside_treats_unresolvable_paths_as_outside(tmp_path: Path) -> None:
    class Unresolvable(PosixPath):
        def resolve(self, strict: bool = False) -> NoReturn:
            msg = f"symlink loop (strict={strict})"
            raise OSError(msg)

    assert _attach._inside(tmp_path, Unresolvable(tmp_path / "loop.txt")) is False
