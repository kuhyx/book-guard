# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""One background job at a time, polled from the Tk thread.

The lock window must never block on a model call (a frozen window with the
grab held looks exactly like a hang), so slow work runs here and the Tk
``after`` loop asks :meth:`OneJob.finish_if_done` whether it has finished.
"""

from __future__ import annotations

from concurrent.futures import Future, ThreadPoolExecutor
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable


def _ignore(_result: object) -> None:
    """The completion for work nobody waits on."""


class OneJob:
    """A single-slot worker: a new job is refused while one is running."""

    def __init__(self) -> None:
        """Start an idle worker."""
        self._executor = ThreadPoolExecutor(max_workers=1)
        self._future: Future[object] | None = None
        self._done: Callable[[object], None] = _ignore

    @property
    def busy(self) -> bool:
        """Whether a job is running or waiting to be collected."""
        return self._future is not None

    def start[T](self, work: Callable[[], T], done: Callable[[T], None]) -> bool:
        """Run ``work`` in the background; ``done`` gets its result later.

        Returns:
            Whether the job was accepted (False while another one is busy).
        """
        if self._future is not None:
            return False
        self._future = cast("Future[object]", self._executor.submit(work))
        self._done = lambda result: done(cast("T", result))
        return True

    def finish_if_done(self) -> bool:
        """Deliver a finished job's result to its ``done``.

        Returns:
            Whether a job finished on this call.

        Raises:
            Exception: Whatever the job raised, re-raised here on the caller's
                thread so the lock can report it.
        """
        future = self._future
        if future is None or not future.done():
            return False
        self._future = None
        self._done(future.result())
        return True

    def shutdown(self) -> None:
        """Stop accepting work; never waits on a running model call."""
        self._executor.shutdown(wait=False, cancel_futures=True)
