# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The evening chain's book rung: what it decides and what it shows.

``lock --production --evening`` ignores the month's pace. The rung is the
day's reading bonus: a signed ``credit`` row with ``detail.bonus == "1"``
that ended today (:func:`earned_time.done_today` on ``READING``, the same
read screen-locker and the orchestrator use). Until that row lands the window
shows the evening goal -- pages read today against the day's bonus line --
and ``gatelock.watch_credit`` takes it down the moment the row appears.

Failure modes, chosen out loud: an unreadable ledger or key is ``None`` and
counts as unpaid, so the window stays up (fail closed); the only ways out are
the credit, "end evening", or no display (exit 3).
"""

from __future__ import annotations

from dataclasses import replace
from datetime import date, datetime, time
import importlib
import logging
from typing import TYPE_CHECKING, Final

import earned_time

from book_guard import _pictos as p

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard._paths import Paths
    from book_guard._state import Snapshot

_logger: Final = logging.getLogger(__name__)

RANK_EVENING: Final = 150
"""gatelock arbitration rank of an evening gate: below screen-locker (200)."""

X_WAIT_S: Final = 10.0
"""Evening mode waits this long for a display, not forever like the morning."""

EXIT_NO_X: Final = 3
"""No X server within :data:`X_WAIT_S`: no window was built."""

_FALLBACK_END: Final = 10


def end_code(load: Callable[[str], object] = importlib.import_module) -> int:
    """The orchestrator's "end evening" exit code, 10 until its module exists."""
    try:
        module = load("gatelock.evening_chain")
    except ImportError:
        _logger.warning("gatelock.evening_chain missing; end code %d", _FALLBACK_END)
        return _FALLBACK_END
    return int(getattr(module, "EXIT_END_EVENING", _FALLBACK_END))


EXIT_END_EVENING: Final = end_code()


def reading_paid(paths: Paths, today: date | None = None) -> bool | None:
    """Whether the reading bonus is paid today; ``None`` when it cannot be read.

    ``today`` (demos and tests only) pins the clock to the end of that day.
    """
    now = None if today is None else datetime.combine(today, time(23, 59)).astimezone()
    verdict: bool | None = earned_time.done_today(
        earned_time.READING, paths.ledger, paths.key_file, now=now
    )
    if verdict is None:
        _logger.error("cannot check the reading rung (ledger or key) -- unpaid")
    return verdict


def goal_gauge(snap: Snapshot) -> p.Gauge:
    """Pages read today against the line that earns the day's hour."""
    return p.Gauge(p.MOON, snap.pace.pages_today, snap.pace.ask.bonus_at)


def evening_view(view: p.View, snap: Snapshot) -> p.View:
    """The lock view for the evening: the goal and the month, shown as locked."""
    return replace(view, locked=True, gauges=(goal_gauge(snap), view.gauges[0]))
