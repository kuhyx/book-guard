# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Signed, CLI-only time corrections that may *widen* a session.

The app's ``session_times`` (:mod:`book_guard._retime`) only narrows: the
photos are the clock, and an unsigned file must never earn anything. But
when the app itself loses a photo (2026-10-23: the phone dropped the 10:0x
start of p. 252, so it was re-photographed after reading, 33 s before the
p. 302 photo), the photos understate the reading. The owner then widens
the session from the CLI, with a reason, as a signed ``retime`` ledger row
(read back by :func:`book_guard._session_times.widened`): nothing the app
or a file edit can write reaches it, and the record keeps why. Once per
session, and never after it was graded.
"""

from __future__ import annotations

from datetime import datetime
import logging
import sys
from typing import TYPE_CHECKING, Final

from book_guard import _ledger, _paths
from book_guard._constants import MIN_SECONDS_PER_PAGE
from book_guard._flock import exclusive
from book_guard._session_times import RETIME, RETIME_PREFIX
from book_guard._state import snapshot

if TYPE_CHECKING:
    import argparse

    from book_guard._state import SessionView

_logger: Final = logging.getLogger(__name__)


class WidenError(ValueError):
    """The correction was refused; the message says why."""


def _refusal(
    view: SessionView, ledger: _ledger.Ledger, start: datetime, end: datetime
) -> str:
    """Why the correction is refused, or ``""``."""
    session = view.session
    needed = session.pages * MIN_SECONDS_PER_PAGE
    checks = (
        (bool(view.verdicts), "This session was already graded."),
        (
            ledger.has(RETIME_PREFIX + session.session_id),
            "This session was already retimed.",
        ),
        (start >= end, "The start must come before the end."),
        (
            (end - start).total_seconds() < needed,
            f"{session.pages} pages need at least {needed // 60} minutes.",
        ),
    )
    return next((message for failed, message in checks if failed), "")


def widen(
    active: _paths.Paths,
    session_id: str,
    start: datetime,
    end: datetime | None,
    reason: str,
) -> str:
    """Record ``session_id`` as read from ``start`` to ``end`` (or its end photo).

    Returns:
        The session as it now reads, for the terminal.

    Raises:
        WidenError: No such session, no reason, already graded or retimed,
            or the new span is still under the 50 s/page rule.
    """
    with exclusive(active):
        view = next(
            (
                v
                for v in snapshot(active).sessions
                if v.session.session_id == session_id
            ),
            None,
        )
        if view is None or not reason.strip():
            msg = "No such session." if view is None else "A reason is required."
            raise WidenError(msg)
        end = end or view.session.ended_at
        ledger = _ledger.load(active.ledger, active.key_file)
        refusal = _refusal(view, ledger, start, end)
        if refusal:
            raise WidenError(refusal)
        _ledger.append(
            active.ledger,
            active.key_file,
            _ledger.Entry(
                entry_id=RETIME_PREFIX + session_id,
                kind=RETIME,
                day=start.astimezone().date().isoformat(),
                detail={
                    "start": start.isoformat(),
                    "end": end.isoformat(),
                    "reason": reason.strip(),
                },
            ),
        )
    session = view.session
    minutes = int((end - start).total_seconds() // 60)
    span = f"{start.astimezone():%H:%M}-{end.astimezone():%H:%M}"
    return f"p. {session.start.page}-{session.end.page}: {span} ({minutes} min)"


def configure(parser: argparse.ArgumentParser) -> None:
    """The ``retime`` subcommand's arguments."""
    parser.add_argument("session")
    parser.add_argument(
        "--start", type=datetime.fromisoformat, required=True, help="ISO time"
    )
    parser.add_argument(
        "--end", type=datetime.fromisoformat, help="ISO time (default: as is)"
    )
    parser.add_argument("--reason", required=True, help="kept in the ledger")


def cmd_retime(args: argparse.Namespace) -> int:
    """``book-guard retime``: widen one session, signed."""
    try:
        line = widen(_paths.paths(), args.session, args.start, args.end, args.reason)
    except WidenError as exc:
        _logger.warning("retime refused: %s", exc)
        sys.stderr.write(f"{exc}\n")
        return 1
    sys.stdout.write(f"retimed {line}\n")
    return 0
