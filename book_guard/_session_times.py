# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Session times the reader narrowed: a later start, an earlier end.

The photos' EXIF times are the session clock, but a start photo is sometimes
taken well before the reading begins (2026-10-03: the p. 51 photo at 12:27,
the reading from ~13:40). The reader may move the start *later* and the end
*earlier* -- never outside the photos. Narrowing only makes the 50 s/page
rule stricter, so it can never earn anything; widening would let a flicked
stretch pass as read, and is refused.

Unsigned on purpose: whatever the file says is clamped to the photos. A
session already graded keeps the times it was graded with (its ledger row
is signed).
"""

from __future__ import annotations

from datetime import datetime
import json
import logging
from typing import TYPE_CHECKING, Final

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._sessions import Session

_logger: Final = logging.getLogger(__name__)

SessionTimes = dict[str, tuple[datetime | None, datetime | None]]


def when(raw: object) -> datetime | None:
    """An ISO time from the app (local if it has no zone), or ``None``."""
    if not isinstance(raw, str) or not raw:
        return None
    try:
        moment = datetime.fromisoformat(raw)
    except ValueError:
        _logger.warning("ignoring a session time that is not ISO: %r", raw)
        return None
    return moment if moment.tzinfo else moment.astimezone()


def load_times(path: Path) -> SessionTimes:
    """Every narrowed session, by id; a missing or broken file is none."""
    if not path.exists():
        return {}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _logger.warning("ignoring unreadable %s (%s)", path, exc)
        return {}
    if not isinstance(raw, dict):
        return {}
    return {
        str(sid): (when(row.get("start")), when(row.get("end")))
        for sid, row in raw.items()
        if isinstance(row, dict)
    }


def apply_times(session: Session, times: SessionTimes) -> None:
    """Narrow ``session`` to its stored times, clamped to its photos."""
    start, end = times.get(session.session_id, (None, None))
    if start is not None and session.start.taken < start < session.end.taken:
        session.started = start
    if end is not None and session.started_at < end < session.end.taken:
        session.ended = end
