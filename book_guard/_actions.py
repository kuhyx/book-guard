# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The operations the CLI, the timer and the lock window share."""

from __future__ import annotations

import logging
import shutil
import subprocess
import time
from typing import TYPE_CHECKING, Final

from book_guard import _ledger
from book_guard._app_handlers import HANDLERS
from book_guard._attach import attach_dropped
from book_guard._books import current, normalise_chapters, register
from book_guard._constants import ESCAPE_PHRASE, UPLOAD_SETTLE_SECONDS
from book_guard._flock import exclusive
from book_guard._grading import register_isbn
from book_guard._inbox import InboxResult, process_inbox, unsettled
from book_guard._ledger import ESCAPE, Entry
from book_guard._openlibrary import BookInfo
from book_guard._publish import write_next_file
from book_guard._render import todo_lines
from book_guard._requests import handle_requests
from book_guard._state import Snapshot, awaiting_quiz, snapshot

if TYPE_CHECKING:
    from book_guard._books import Chapter
    from book_guard._paths import Paths
    from book_guard._state import SessionView

_logger: Final = logging.getLogger(__name__)

_SETTLE_WAIT_MAX: Final = 120.0
"""Longest a run waits for in-flight uploads before leaving them to the timer."""


def _notify(lines: list[str]) -> None:
    """A desktop notification with the new to-dos; silently skipped headless."""
    notifier = shutil.which("notify-send")
    if notifier and lines:
        subprocess.run(
            [notifier, "book-guard", "\n".join(lines)], check=False, timeout=10
        )


def process(
    paths: Paths, *, now: float | None = None, settle_wait: bool = True
) -> tuple[InboxResult, Snapshot]:
    """Read the inbox, register scanned barcodes, refresh NEXT.txt.

    Notifies only when this pass read something, so the 15-minute fallback
    timer stays quiet on an empty inbox.
    """
    with exclusive(paths):
        result = process_inbox(paths, now=now)
    # The .path unit fires as an upload *starts*, and events that land while
    # this run is active are not queued -- so a file still being written is
    # waited for here rather than left for the 15-minute fallback timer.
    waited = 0.0
    while (
        settle_wait
        and now is None
        and unsettled(paths.inbox)
        and waited < _SETTLE_WAIT_MAX
    ):
        time.sleep(UPLOAD_SETTLE_SECONDS)
        waited += UPLOAD_SETTLE_SECONDS
        with exclusive(paths):
            more = process_inbox(paths)
        result.read += more.read
        result.duplicates += more.duplicates
        result.new_isbns += more.new_isbns
        result.deferred = more.deferred
    for isbn in result.new_isbns:
        _logger.info("%s", register_isbn(paths, isbn)[1])
    for chapters in result.contents:
        _logger.info("%s", add_chapters(paths, chapters))
    # Requests and dropped book files after the photos, and outside the
    # write lock: their handlers take it themselves around each write, and a
    # grading call or a book index must not hold up the next photo pass.
    handle_requests(paths, HANDLERS)
    attached = attach_dropped(paths)
    snap = snapshot(paths)
    write_next_file(paths, snap)
    if result.read or attached:
        _notify(todo_lines(snap) + attached)
    return result, snap


def add_chapters(paths: Paths, chapters: tuple[Chapter, ...]) -> str:
    """Merge a contents photo's chapters into the current book's list."""
    with exclusive(paths):
        book = current(_ledger.load(paths.ledger, paths.key_file))
        if book is None:
            return "contents photo read, but no book is registered to attach it to"
        merged = normalise_chapters([*book.chapters, *chapters])
        info = BookInfo(book.title, book.author, book.pages, book.isbn)
        register(paths, info, chapters=merged)
    return f"{book.label}: {len(merged)} chapters"


def next_quiz(paths: Paths, *, session_id: str | None = None) -> SessionView | None:
    """The session to grade: ``session_id`` if given, else the oldest waiting."""
    pending = awaiting_quiz(snapshot(paths))
    if session_id is not None:
        pending = [v for v in pending if v.session.session_id == session_id]
    return pending[0] if pending else None


def escape_today(paths: Paths, typed: str) -> str | None:
    """Spend one escape on today; returns an error message, or ``None``.

    The escape forgives today's lock only. It credits no pages, so the
    deficit is still there tomorrow -- it buys a day, not a month.
    """
    snap = snapshot(paths)
    if snap.escapes_left <= 0:
        return "No escapes left this month."
    if " ".join(typed.split()) != ESCAPE_PHRASE:
        return f'Type exactly: "{ESCAPE_PHRASE}"'
    day = snap.today.isoformat()
    with exclusive(paths):
        _ledger.append(
            paths.ledger, paths.key_file, Entry(f"escape:{day}", ESCAPE, day)
        )
    return None
