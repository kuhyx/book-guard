# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Summaries are graded off the photo pass (``book-guard grade``).

kuhy, 2026-11-24: nothing may wait longer than a second. A grading call
takes Claude 10-60 s (the local model longer), so the photo pass leaves
summary requests in place and only starts ``book-guard-grade.service``; a
photo is published at once, never behind a summary. One grade run at a
time (``grade.lock``, never the ledger's ``write.lock``: the handlers take
that themselves around each write).
"""

from __future__ import annotations

from contextlib import contextmanager
import fcntl
import logging
from typing import TYPE_CHECKING, Final

from book_guard import _paths
from book_guard._app_handlers import HANDLERS
from book_guard._publish import write_next_file
from book_guard._requests import GRADED, handle_requests, pending_kinds
from book_guard._state import snapshot

if TYPE_CHECKING:
    import argparse
    from collections.abc import Iterator

    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

GRADE_UNIT: Final = "book-guard-grade.service"


@contextmanager
def grade_lock(paths: Paths) -> Iterator[bool]:
    """Try to become the one grade run; yields whether that worked."""
    paths.data_dir.mkdir(parents=True, exist_ok=True)
    with (paths.data_dir / "grade.lock").open("w") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            _logger.warning("grade.lock is held: another grade run is going")
            yield False
            return
        try:
            yield True
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def waiting(paths: Paths) -> bool:
    """Whether a summary request waits for the grader."""
    return bool(pending_kinds(paths) & GRADED)


def grade_pass(paths: Paths) -> int | None:
    """Grade every waiting summary; ``None`` if another run has the lock.

    Loops while new summaries arrive, since the unit is not started again
    while it runs. A summary deferred by an outage stays for the next run.
    """
    with grade_lock(paths) as mine:
        if not mine:
            return None
        answered = 0
        while more := handle_requests(paths, HANDLERS, only=GRADED):
            answered += more
        if answered:
            write_next_file(paths, snapshot(paths))
        return answered


def cmd_grade(_args: argparse.Namespace) -> int:
    """``book-guard grade``: the grade unit's one job."""
    answered = grade_pass(_paths.paths())
    _logger.info(
        "another grade run is going" if answered is None else f"graded {answered}"
    )
    return 0
