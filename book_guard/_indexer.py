# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Book-file indexing as its own background job -- photos always come first.

The photo pass (``process``) never indexes: a book takes minutes, and a
oneshot pass busy embedding drops every inbox event meanwhile. It only
notices files in ``Reading/books/``, marks the job ``uploaded`` and starts
``book-guard-index.service`` without waiting (the unit's own path unit and
timer start it too). That unit runs ``book_guard index`` at idle CPU and IO
priority with no deadline: :func:`book_guard._embed.build` checkpoints, so a
kill or a reboot resumes the book instead of restarting it.

Two index runs never overlap (``index.lock``, separate from the ledger's
``write.lock``, which indexing never takes: it writes no ledger row).
"""

from __future__ import annotations

from contextlib import contextmanager
import fcntl
import logging
import os
import shutil
import subprocess
from typing import TYPE_CHECKING, Final

from book_guard import _indexjob
from book_guard._attach import attach_dropped
from book_guard._booktext import SUPPORTED

if TYPE_CHECKING:
    from collections.abc import Iterator
    from pathlib import Path

    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

INDEX_UNIT: Final = "book-guard-index.service"


@contextmanager
def index_lock(paths: Paths) -> Iterator[bool]:
    """Try to become the one index run; yields whether that worked."""
    paths.data_dir.mkdir(parents=True, exist_ok=True)
    with (paths.data_dir / "index.lock").open("w") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            _logger.warning("index.lock is held: another index run is going")
            yield False
            return
        try:
            yield True
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def queued(paths: Paths) -> list[Path]:
    """Book files waiting in ``Reading/books/``, in the order they are indexed."""
    folder = paths.books
    if not folder.is_dir():
        return []
    return sorted(
        p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in SUPPORTED
    )


def mark_queued(paths: Paths) -> bool:
    """Mark the next waiting file ``uploaded``; returns whether any waits.

    Left alone while an index run holds the lock (it writes its own stages),
    and never rewritten for the same file: a job stuck at ``uploaded`` must
    age into the app's 30-minute "stopped" rule if the unit never runs.
    """
    files = queued(paths)
    if not files:
        return False
    job = _indexjob.load(paths) or {}
    if job.get("stage") in {"extracting", "embedding"}:
        return True  # a run is (or was, until the app calls it stale) at it
    with index_lock(paths) as free:
        name = files[0].name
        if free and (job.get("file"), job.get("stage")) != (name, "uploaded"):
            _indexjob.write(paths, name, "uploaded")
    return True


def kick() -> None:
    """Start the index unit without waiting; a sandbox runs ``index`` by hand."""
    if os.environ.get("BOOK_GUARD_ROOT"):
        _logger.info("sandbox: book files wait for `book_guard index`")
        return
    systemctl = shutil.which("systemctl")
    if systemctl is None:
        _logger.warning("no systemctl; %s not started", INDEX_UNIT)
        return
    done = subprocess.run(
        [systemctl, "--user", "start", "--no-block", INDEX_UNIT],
        check=False,
        timeout=10,
        capture_output=True,
        text=True,
    )
    if done.returncode != 0:
        _logger.warning("could not start %s: %s", INDEX_UNIT, done.stderr.strip())


def run_index(paths: Paths) -> list[str] | None:
    """Index every waiting book file; ``None`` if another run has the lock.

    Loops until ``books/`` is empty, so a file dropped mid-run (whose path
    event the busy oneshot unit dropped) is not left for the timer.
    """
    with index_lock(paths) as mine:
        if not mine:
            return None
        messages: list[str] = []
        while batch := attach_dropped(paths):
            messages += batch
        return messages
