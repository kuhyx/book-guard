# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``book-guard index``: embed the book files the app uploaded."""

from __future__ import annotations

import logging
import sys
from typing import TYPE_CHECKING, Final

from book_guard import _ebook
from book_guard._actions import notify
from book_guard._embed import EmbedderUnavailableError
from book_guard._indexer import run_index
from book_guard._paths import paths
from book_guard._pictos import BOOK, GLYPH, OK

if TYPE_CHECKING:
    import argparse

_logger: Final = logging.getLogger(__name__)


def _out(text: str) -> None:
    sys.stdout.write(text + "\n")


def cmd_index(_args: argparse.Namespace) -> int:
    """Index book files dropped into ``Reading/books`` (``book-guard index``)."""
    try:
        messages = run_index(paths())
    except EmbedderUnavailableError as exc:
        # The book stays queued and its checkpoint kept: a run on a Python
        # with fastembed resumes it.
        _logger.warning("index failed: %s", exc)
        sys.stderr.write(f"{exc}\n")
        return 1
    if messages is None:
        _out("another index run is going; it picks up new files too")
        return 0
    if messages and _ebook.refresh(paths()):
        messages.append("in-app reader: page map ready")
    for message in messages:
        _out(message)
    if messages:
        notify(f"{GLYPH[BOOK]} {GLYPH[OK]}", icon="emblem-ok")
    return 0
