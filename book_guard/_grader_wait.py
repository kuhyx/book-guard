# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The outage clock: how long a summary has waited on an unreachable grader.

A session's clock starts when its grading starts (kuhy, 2026-11-24: the
grace runs from the submit, not from Claude's timeout); a graded summary
stops it. Past :data:`GRADER_GRACE` the summary is credited ungraded, so
Claude being down (or out of usage) never blocks the reader for long.
"""

from __future__ import annotations

from datetime import UTC, datetime
import json
import logging
from typing import TYPE_CHECKING, Final

from book_guard._atomic_json import write_json
from book_guard._constants import GRADER_GRACE
from book_guard._flock import exclusive

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)


def clock_file(paths: Paths) -> Path:
    """When each summary's grading first failed, by session id."""
    return paths.data_dir / "grader_waits.json"


def _load(paths: Paths) -> dict[str, str]:
    target = clock_file(paths)
    if not target.exists():  # no outage so far: nothing is waiting
        return {}
    try:
        raw = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        # A torn clock restarts the wait: it can only delay a credit.
        _logger.warning("unreadable %s (%s); restarting", target, exc)
        return {}
    return {str(k): str(v) for k, v in raw.items()} if isinstance(raw, dict) else {}


def _now() -> datetime:
    return datetime.now(tz=UTC)


def start(paths: Paths, session_id: str, *, now: datetime | None = None) -> None:
    """Start ``session_id``'s clock unless it already runs."""
    moment = now or _now()
    with exclusive(paths):
        waits = _load(paths)
        if session_id not in waits:
            waits[session_id] = moment.isoformat()
            write_json(clock_file(paths), waits, indent=1)


def waited_out(paths: Paths, session_id: str, *, now: datetime | None = None) -> bool:
    """Note a failed grading of ``session_id``; whether the grace has passed."""
    moment = now or _now()
    with exclusive(paths):
        waits = _load(paths)
        first = waits.setdefault(session_id, moment.isoformat())
        write_json(clock_file(paths), waits, indent=1)
    return moment - datetime.fromisoformat(first) >= GRADER_GRACE


def left(paths: Paths, session_id: str) -> float:
    """Seconds of ``session_id``'s grace left (all of it before its clock)."""
    first = _load(paths).get(session_id)
    gone = (_now() - datetime.fromisoformat(first)).total_seconds() if first else 0
    return GRADER_GRACE.total_seconds() - gone


def stop(paths: Paths, session_id: str) -> None:
    """The summary was graded (or credited): forget its clock."""
    with exclusive(paths):
        waits = _load(paths)
        if waits.pop(session_id, None) is not None:
            write_json(clock_file(paths), waits, indent=1)
