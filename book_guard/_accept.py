# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Signed, CLI-only credit of one session without the grader.

Nothing else credits without the grader (or its :data:`GRADER_GRACE`). The
owner may still vouch for a session from the CLI, with a reason: the
session is credited as it stands, waiting for its check photo or its
summary, through the normal :func:`book_guard._quiz.record_verdict` (so the
day's bonus and inclusive counting apply as usual), marked
``detail.graded == "0"`` and ``detail.grader == "manual"``. The app and the
request files cannot reach it. A too-fast session is still refused: the
speed floor is the one thing a hand credit does not override (``retime``
widens a session the phone lost a photo of).
"""

from __future__ import annotations

import logging
import sys
from typing import TYPE_CHECKING, Final

from book_guard import _paths
from book_guard._flock import exclusive
from book_guard._publish import write_next_file
from book_guard._quiz import Verdict, record_verdict
from book_guard._sessions import TOO_FAST
from book_guard._state import snapshot
from book_guard._widen import find_view

if TYPE_CHECKING:
    import argparse

    from book_guard._ledger import Entry

_logger: Final = logging.getLogger(__name__)

MANUAL: Final = "manual"
"""``detail.grader`` of a row credited by :func:`accept`."""


class AcceptError(ValueError):
    """The credit was refused; the message says why."""


def accept(active: _paths.Paths, session_id: str, reason: str) -> Entry:
    """Credit ``session_id`` by hand.

    Raises:
        AcceptError: No such session, no reason, too fast, or already credited.
    """
    with exclusive(active):
        view = find_view(active, session_id)
        if view is None or not reason.strip():
            msg = "No such session." if view is None else "A reason is required."
            raise AcceptError(msg)
        if view.status == TOO_FAST:
            msg = "This session is too fast to count."
            raise AcceptError(msg)
        verdict = Verdict(
            passed=True,
            feedback=f"accepted by hand: {reason.strip()}",
            ungraded=True,
            grader=MANUAL,
        )
        # None: a credit row already stands (record_verdict checks the ledger).
        entry = record_verdict(active, view.book, view.session, verdict, "")
        if entry is None:
            msg = "This session was already credited."
            raise AcceptError(msg)
    write_next_file(active, snapshot(active))
    return entry


def configure(parser: argparse.ArgumentParser) -> None:
    """The ``accept`` subcommand's arguments."""
    parser.add_argument("session")
    parser.add_argument("--reason", required=True, help="kept in the ledger")


def cmd_accept(args: argparse.Namespace) -> int:
    """``book-guard accept``: credit one session without the grader, signed."""
    try:
        entry = accept(_paths.paths(), args.session, args.reason)
    except AcceptError as exc:
        _logger.warning("accept refused: %s", exc)
        sys.stderr.write(f"{exc}\n")
        return 1
    detail = entry.detail
    sys.stdout.write(
        f"accepted p. {detail['start_page']}-{detail['end_page']}: "
        f"{entry.amount} pages\n"
    )
    return 0
