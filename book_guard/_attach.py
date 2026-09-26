# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Attach an ebook file to a registered book and index it.

Files arrive two ways: ``book-guard attach FILE`` on the PC, or dropped into
``Reading/books/`` from the phone or desktop app. Either way the file is
copied under the data dir (the WebDAV folder is the phone's to delete from),
its text extracted in whatever format it is, and indexed for anchoring.
"""

from __future__ import annotations

import logging
import shutil
from typing import TYPE_CHECKING, Final

from book_guard import _ledger
from book_guard._books import current
from book_guard._booktext import SUPPORTED, BookTextError, extract
from book_guard._embed import build

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)


def attach(paths: Paths, source: Path, *, isbn: str | None = None) -> str:
    """Index ``source`` for ``isbn`` (default: the current book).

    Returns:
        A line for the human.

    Raises:
        BookTextError: No book to attach to, or the file yields no text.
    """
    if isbn is None:
        book = current(_ledger.load(paths.ledger, paths.key_file))
        if book is None:
            msg = "register the book first, then attach its file"
            raise BookTextError(msg)
        isbn = book.isbn
    text = extract(source)
    stored = paths.data_dir / "books" / f"{isbn}{source.suffix.lower()}"
    stored.parent.mkdir(parents=True, exist_ok=True)
    if source.resolve() != stored.resolve():
        shutil.copyfile(source, stored)
    chunks = build(paths, isbn, text, source=source.name)
    return (
        f"Attached {source.name}: {len(text):,} characters, {chunks} passages indexed"
    )


def _inside(directory: Path, candidate: Path) -> bool:
    """Whether ``candidate`` really lives in ``directory`` (no symlink escape)."""
    try:
        return candidate.resolve().is_relative_to(directory.resolve())
    except OSError as exc:
        _logger.warning("cannot resolve %s (%s); skipping it", candidate, exc)
        return False


def attach_dropped(paths: Paths) -> list[str]:
    """Attach every book file dropped into ``Reading/books/``; returns messages.

    A handled file is moved to ``books/done/`` (or ``books/failed/`` with the
    reason in a ``.txt`` beside it) so it is never indexed twice.
    """
    folder = paths.books
    if not folder.is_dir():
        return []
    messages = []
    for path in sorted(folder.iterdir()):
        if not path.is_file() or not _inside(folder, path):
            continue
        if path.suffix.lower() not in SUPPORTED:
            continue
        try:
            message = attach(paths, path)
            outcome = "done"
        except BookTextError as exc:
            _logger.warning("could not attach %s: %s", path.name, exc)
            message = f"{path.name}: {exc}"
            outcome = "failed"
            (folder / outcome).mkdir(exist_ok=True)
            (folder / outcome / f"{path.name}.txt").write_text(
                message + "\n", encoding="utf-8"
            )
        _logger.info("%s", message)
        (folder / outcome).mkdir(exist_ok=True)
        path.replace(folder / outcome / path.name)
        messages.append(message)
    return messages
