# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Attach an ebook file to a registered book and index it.

Files arrive two ways: ``book-guard attach FILE`` on the PC, or dropped into
``Reading/books/`` from the phone or desktop app. Either way the file is
copied under the data dir (the WebDAV folder is the phone's to delete from),
its text extracted in whatever format it is, and indexed for anchoring.
"""

from __future__ import annotations

import logging
from pathlib import Path
import shutil
from typing import TYPE_CHECKING, Final

from book_guard import _indexjob, _ledger
from book_guard._books import current
from book_guard._booktext import SUPPORTED, BookTextError, extract
from book_guard._embed import build

if TYPE_CHECKING:
    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)


def _current_isbn(paths: Paths) -> str:
    """The registered book's ISBN; raises ``BookTextError`` without one."""
    book = current(_ledger.load(paths.ledger, paths.key_file))
    if book is None:
        msg = "register the book first, then attach its file"
        raise BookTextError(msg)
    return book.isbn


def attach(paths: Paths, source: Path, *, isbn: str | None = None) -> str:
    """Index ``source`` for ``isbn`` (default: the current book).

    Every stage lands in the app's ``index_job`` (:mod:`_indexjob`); a job
    that ends any other way than ``done`` is recorded as ``failed`` with the
    reason, then the error propagates.

    Returns:
        A line for the human.

    Raises:
        BookTextError: No book to attach to, or the file yields no text.
    """
    name = source.name
    try:
        _indexjob.write(paths, name, "extracting")
        isbn = isbn or _current_isbn(paths)
        text = extract(source)
        stored = paths.data_dir / "books" / f"{isbn}{source.suffix.lower()}"
        stored.parent.mkdir(parents=True, exist_ok=True)
        if source.resolve() != stored.resolve():
            shutil.copyfile(source, stored)
        chunks = build(
            paths, isbn, text, source=name, progress=_indexjob.Progress(paths, name)
        )
        _indexjob.write(paths, name, "done", progress=(chunks, chunks))
        return f"Attached {name}: {len(text):,} characters, {chunks} passages indexed"
    except BookTextError as exc:
        _indexjob.write(paths, name, "failed", error=f"{name}: {exc}")
        raise
    except Exception as exc:
        # Anything else (a model download, the disk) still propagates, but
        # the app must not show "embedding" until the 30-minute rule.
        crash = f"{name}: indexing crashed ({type(exc).__name__}: {exc})"
        _indexjob.write(paths, name, "failed", error=crash)
        raise


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
        _indexjob.write(paths, path.name, "uploaded")
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


def requeue(paths: Paths, name: str) -> str:
    """Move ``books/failed/<name>`` back into ``books/`` for the next pass.

    The same name already sitting in ``books/`` is a newer upload, already
    queued: it wins, and the failed copy and its reason are dropped.

    Returns:
        A line for the human.

    Raises:
        BookTextError: ``name`` is not a plain file name, or nothing by that
            name failed or waits.
    """
    folder = paths.books
    if not name or Path(name).name != name or name.startswith("."):
        msg = f"{name!r} is not a book file name"
        raise BookTextError(msg)
    failed = folder / "failed" / name
    reason = folder / "failed" / f"{name}.txt"
    queued = folder / name
    if queued.is_file():
        failed.unlink(missing_ok=True)
        reason.unlink(missing_ok=True)
        _indexjob.write(paths, name, "uploaded")
        return f"{name} is already queued (a newer upload); it is indexed next"
    if not failed.is_file() or not _inside(folder / "failed", failed):
        msg = f"no failed book file named {name}"
        raise BookTextError(msg)
    failed.replace(queued)
    reason.unlink(missing_ok=True)
    _indexjob.write(paths, name, "uploaded")
    return f"{name} queued again"
