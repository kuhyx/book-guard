# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``book-guard quiz``: write the summary for a finished session."""

from __future__ import annotations

import logging
import sys
from typing import TYPE_CHECKING, Final

from book_guard._actions import next_quiz
from book_guard._claude import DEFAULT_MODEL, ClaudeUnavailableError
from book_guard._grading import quiz_one
from book_guard._paths import paths
from book_guard._render import session_line

if TYPE_CHECKING:
    import argparse

_logger: Final = logging.getLogger(__name__)


def _say(line: str, *, err: bool = False) -> None:
    (sys.stderr if err else sys.stdout).write(line + "\n")


def _read_summary() -> str:
    _say("Summary (3-5 sentences; finish with an empty line):")
    lines: list[str] = []
    for line in sys.stdin:
        if not line.strip():
            break
        lines.append(line.rstrip("\n"))
    return " ".join(lines)


def configure(parser: argparse.ArgumentParser) -> None:
    """The ``quiz`` subcommand's arguments."""
    parser.add_argument("--session", help="grade this session id (default: oldest)")
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help="grader for this run only (default: haiku)",
    )


def cmd_quiz(args: argparse.Namespace) -> int:
    """Grade the summary typed on stdin for one waiting session."""
    active = paths()
    view = next_quiz(active, session_id=args.session)
    if view is None:
        _say("Nothing waiting for a summary.")
        return 0
    _say(
        f"{view.book.label if view.book else 'Unregistered book'}: {session_line(view)}"
    )
    try:
        verdict = quiz_one(active, view, _read_summary(), model=args.model)
    except ClaudeUnavailableError as exc:
        _logger.warning("grader unavailable: %s", exc)
        _say(f"Grader unavailable ({exc}); the session stays open.", err=True)
        return 1
    _say(("PASSED: " if verdict.passed else "FAILED: ") + verdict.feedback)
    return 0 if verdict.passed else 1
