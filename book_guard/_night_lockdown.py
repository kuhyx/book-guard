# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Do not re-arm the gate after tonight's evening night-lockdown.

Same signal as screen-locker and leetcode-guard (diet-guard deliberately
does not opt in): night-lockdown stamps the epoch of its latest lock, and
gatelock's shared reader is the whole decision -- local date today, local
time >= 12:00, so the 04:01 morning re-lock does not count. Once tonight's
lockdown fired, a late credit can lift it, and re-locking behind the reading
gate the same evening would make a finished session impossible to submit.

A run deferral, never ledger state, exactly like the morning carrot. Missing
or garbage stamp means "lock as usual". The sandbox reads its own stamp
under ``BOOK_GUARD_ROOT``.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from gatelock.night_lockdown import evening_lockdown_today

from book_guard._morning import morning_skip_for

if TYPE_CHECKING:
    from datetime import datetime

    from gatelock.morning_session import MorningSkip

    from book_guard._paths import Paths


def evening_lockdown_for(paths: Paths, now: datetime | None = None) -> str | None:
    """Why tonight's lockdown holds the gate, or None to lock as usual."""
    locked_at = evening_lockdown_today(paths.night_lockdown, now)
    if locked_at is None:
        return None
    return (
        f"night lockdown already locked tonight at {locked_at:%H:%M}; "
        "no re-arm after it"
    )


def gate_hold(paths: Paths, *, wait: bool) -> MorningSkip | str | None:
    """What holds this arming run: the morning carrot, else tonight's lockdown.

    ``wait`` is the morning reader's bounded boot retry (production only);
    the lockdown stamp is local and never waited for.
    """
    return morning_skip_for(paths, wait=wait) or evening_lockdown_for(paths)
