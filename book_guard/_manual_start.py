# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``book-guard start``: open a paper session without a start photo.

When the app cannot take the start photo (2026-11-22: a 26-day-old stored
photo hid the camera button), the owner opens the session from the CLI,
with a reason, as a signed ``start:`` ledger row. Nothing the app, the MCP
server or a file edit can write reaches it. From the stop photo on the
session is judged as any other (the clock runs from ``--at``, the 38 s/page
floor, the check page, the grader); its credit row carries
``detail.start == "manual"``. How the row becomes a start record:
:mod:`book_guard._manual_pages`.
"""

from __future__ import annotations

from datetime import datetime
import logging
import sys
from typing import TYPE_CHECKING, Final

from book_guard import _ledger, _paths
from book_guard._books import current
from book_guard._flock import exclusive
from book_guard._manual_pages import (
    KIND,
    PREFIX,
    log_replacement,
    pages,
    replaced_by,
)
from book_guard._state import snapshot

if TYPE_CHECKING:
    import argparse

    from book_guard._sessions import Session

__all__ = ["KIND", "StartError", "log_replacement", "pages", "replaced_by", "start"]

_logger: Final = logging.getLogger(__name__)


class StartError(ValueError):
    """The start was refused; the message says why."""


def _now() -> datetime:
    """The clock ``--at`` is checked against (the tests' seam)."""
    return datetime.now().astimezone()


def page_floor(last: Session | None) -> int:
    """The page a new start must be above: the last session's stop page.

    An in-app session's end is the first page *not* read, so that page may
    start the next one.
    """
    if last is None:
        return 0
    stop = int(last.end.page or 0)
    return stop - 1 if last.ebook is not None else stop


def _refusal(paths: _paths.Paths, page: int, at: datetime, now: datetime) -> str:
    """Why the start is refused, or ``""``."""
    snap = snapshot(paths)
    ended = [v.session for v in snap.sessions]
    last = max(ended, key=lambda s: s.ended_at, default=None)
    floor = page_floor(last)
    checks = (
        (snap.book is None, "No book registered yet."),
        (at > now, "--at is in the future."),
        (at.astimezone().date() != now.date(), "--at must be today."),
        (
            last is not None and at <= last.ended_at,
            "--at must come after the last session's stop"
            + (f" ({last.ended_at.astimezone():%H:%M})." if last else "."),
        ),
        (page <= floor, f"--page must be above p. {floor}."),
        (snap.open_start is not None, "A start is already open."),
    )
    return next((message for failed, message in checks if failed), "")


def start(
    paths: _paths.Paths,
    *,
    page: int,
    at: datetime,
    reason: str,
    isbn: str | None = None,
) -> str:
    """Record that reading began on ``page`` at ``at``, signed.

    Returns:
        The start as the terminal shows it.

    Raises:
        StartError: No book or reason, ``at`` not earlier today and after the
            last stop, ``page`` not above the last stop, or a start is open.
    """
    at = at.astimezone()
    with exclusive(paths):
        refusal = _refusal(paths, page, at, _now())
        if not refusal and not reason.strip():
            refusal = "A reason is required."
        if refusal:
            raise StartError(refusal)
        book = current(_ledger.load(paths.ledger, paths.key_file))
        _ledger.append(
            paths.ledger,
            paths.key_file,
            _ledger.Entry(
                entry_id=f"{PREFIX}{at.isoformat()}",
                kind=KIND,
                day=at.date().isoformat(),
                detail={
                    "page": str(page),
                    "at": at.isoformat(),
                    "isbn": isbn or (book.isbn if book else ""),
                    "reason": reason.strip(),
                },
            ),
        )
    return f"p. {page} at {at:%a %H:%M}"


def configure(parser: argparse.ArgumentParser) -> None:
    """The ``start`` subcommand's arguments."""
    parser.add_argument("--page", type=int, required=True)
    parser.add_argument(
        "--at", type=datetime.fromisoformat, required=True, help="ISO time, today"
    )
    parser.add_argument("--isbn", help="default: the current book")
    parser.add_argument("--reason", required=True, help="kept in the ledger")


def cmd_start(args: argparse.Namespace) -> int:
    """``book-guard start``: open a session without a start photo."""
    try:
        line = start(
            _paths.paths(),
            page=args.page,
            at=args.at,
            reason=args.reason,
            isbn=args.isbn,
        )
    except StartError as exc:
        _logger.warning("start refused: %s", exc)
        sys.stderr.write(f"{exc}\n")
        return 1
    sys.stdout.write(f"started {line}\n")
    return 0
