# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Claude's grading votes, and when not to ask Claude at all.

kuhy, 2026-11-24: the app must work as well with no Claude usage left. A
known outage (a usage cap with its reset time) sends every vote straight
to the local model; one failed vote cancels the votes not yet started.
"""

from __future__ import annotations

from concurrent.futures import FIRST_EXCEPTION, ThreadPoolExecutor, wait
from typing import TYPE_CHECKING

from book_guard import _errlog, _paths
from book_guard._claude import ClaudeUnavailableError

if TYPE_CHECKING:
    from collections.abc import Callable


def claude_known_out() -> bool:
    """A live outage whose reset is known: asking Claude now only waits."""
    outage = _errlog.claude_outage(_paths.paths())
    return outage is not None and outage.until is not None


def claude_votes(
    asker: Callable[..., dict[str, object]],
    count: int,
    system: str,
    prompt: str,
    model: str,
) -> list[dict[str, object]]:
    """``count`` answers side by side; the first failure is raised.

    A known outage raises before any call.

    The failure cancels the votes still queued and is raised at once,
    without joining the ones already running (their subprocess ends on its
    own timeout).
    """
    if claude_known_out():
        msg = "Claude is out until its reset"
        raise ClaudeUnavailableError(msg)
    pool = ThreadPoolExecutor(max_workers=count)
    futures = [pool.submit(asker, system, prompt, model=model) for _ in range(count)]
    done, _ = wait(futures, return_when=FIRST_EXCEPTION)
    failed = next((exc for f in done if (exc := f.exception()) is not None), None)
    pool.shutdown(wait=failed is None, cancel_futures=True)
    if failed is not None:
        raise failed
    return [f.result() for f in futures]
