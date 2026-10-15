# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Where the indexing of a dropped book file stands, for the app's Book tab.

One job at a time (``attach_dropped`` handles files one by one). The job is
kept in ``data_dir/index_job.json`` -- so every later state.json write
carries it (:func:`book_guard._state_json.to_json` reads it) -- and patched
straight into state.json on every change, so the app sees the stages and the
embedding progress while the pass is still running, minutes before the
pass's own state.json write.

Neither write takes the ledger lock: indexing runs outside it on purpose (a
book must not hold up the next photo pass), and both writes are atomic. A
concurrent state.json writer can at worst drop one progress update, which
the next update restores.
"""

from __future__ import annotations

from datetime import UTC, datetime
import json
import logging
import time
from typing import TYPE_CHECKING, Any, Final, Literal

from book_guard._atomic_json import write_json

if TYPE_CHECKING:
    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

type Stage = Literal["uploaded", "extracting", "embedding", "done", "failed"]

PROGRESS_EVERY: Final = 1.0
"""Seconds between two embedding-progress writes; stage changes always write."""


def load(paths: Paths) -> dict[str, Any] | None:
    """The last job written, or ``None`` (never indexed, or unreadable)."""
    if not paths.index_job.exists():
        return None
    try:
        raw = json.loads(paths.index_job.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _logger.warning("unreadable index job (%s); showing none", exc)
        return None
    return raw if isinstance(raw, dict) else None


def write(
    paths: Paths,
    file: str,
    stage: Stage,
    *,
    progress: tuple[int, int] = (0, 0),
    error: str = "",
) -> None:
    """Record the job and patch it into state.json; best effort, never raises.

    ``progress`` is ``(done, total)`` chunks embedded.

    A failed write is logged: progress is a convenience, the attach itself
    (and its ``books/failed/<f>.txt``) is the record.
    """
    job = {
        "file": file,
        "stage": stage,
        "done": progress[0],
        "total": progress[1],
        "error": error,
        "updated_at": datetime.now(tz=UTC).isoformat(),
    }
    try:
        write_json(paths.index_job, job, indent=1)
        _patch_state(paths, job)
    except OSError as exc:
        _logger.warning("could not record the index job (%s)", exc)


def _patch_state(paths: Paths, job: dict[str, Any]) -> None:
    """Set ``index_job`` in the published state.json, if there is one yet.

    With no state.json the pass's own write at its end publishes the job;
    a stub file here would show the app an empty snapshot.
    """
    if not paths.state_file.exists():
        return
    try:
        state = json.loads(paths.state_file.read_text(encoding="utf-8"))
    except ValueError as exc:
        _logger.warning("state.json unreadable (%s); job left for the pass", exc)
        return
    if not isinstance(state, dict):
        return
    state["index_job"] = job
    write_json(paths.state_file, state, indent=1)


class Progress:
    """The embedding progress callback: writes at most every ``PROGRESS_EVERY``."""

    def __init__(self, paths: Paths, file: str) -> None:
        """Track the job for ``file``."""
        self._paths = paths
        self._file = file
        self._last = 0.0

    def __call__(self, done: int, total: int) -> None:
        """``done`` of ``total`` chunks embedded; the first and last always write."""
        now = time.monotonic()
        if 0 < done < total and now - self._last < PROGRESS_EVERY:
            return
        self._last = now
        write(self._paths, self._file, "embedding", progress=(done, total))
