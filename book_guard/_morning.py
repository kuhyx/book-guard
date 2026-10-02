# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Hold the gate while the phone's morning session is earning the carrot.

Same carrot as screen-locker and leetcode-guard: wake-alarm signs today's
morning into ``morning_session.json`` with an ``exempt_until`` (11:00 for a
morning completed in time), and gatelock's shared reader is the whole
decision -- signed, dated today, now < exempt_until. Missing, stale, failed
or tampered all mean "lock as usual".

A run deferral, never ledger state: nothing is written, so the next run
(login, the 11:00:30 slot) decides again. The sandbox reads its own file
under ``BOOK_GUARD_ROOT``, so a demo never depends on the real morning.
"""

from __future__ import annotations

import time
from typing import TYPE_CHECKING

from gatelock.morning_session import (
    MORNING_RETRY_SECONDS as _SHARED_RETRY_SECONDS,
)
from gatelock.morning_session import (
    MorningSkip,
    morning_skip,
)

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard._paths import Paths

MORNING_RETRY_SECONDS: float = _SHARED_RETRY_SECONDS


def morning_skip_for(
    paths: Paths,
    *,
    wait: bool,
    sleep: Callable[[float], None] = time.sleep,
) -> MorningSkip | None:
    """The skip the morning earned right now, or None to lock as usual.

    ``wait`` (the production arming run only) gives a PC booted mid-morning
    a bounded chance for wake-alarm's catch-up to land before deciding.
    """
    return morning_skip(
        paths.morning_session,
        wait=wait,
        retry_seconds=MORNING_RETRY_SECONDS,
        sleep=sleep,
    )
