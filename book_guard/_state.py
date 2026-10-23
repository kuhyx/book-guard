# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""One snapshot of everything: sessions with verdicts, pace, and the verdict.

Every surface -- the lock window, the CLI, NEXT.txt, the MCP server -- renders
this one object, so they can never disagree about what is owed.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import TYPE_CHECKING

import freedays

from book_guard import _ledger, _photos, _sick
from book_guard._books import Book, book_at, current
from book_guard._constants import (
    DAILY_PASS_PAGES,
    ESCAPES_PER_MONTH,
    GATE_START_DATE,
    RESPLIT_DATE,
)
from book_guard._daily_lock import kept, one_number
from book_guard._ledger import ESCAPE
from book_guard._pace import Pace, compute_pace
from book_guard._quiz import credited
from book_guard._session_times import (
    SessionTimes,
    apply_times,
    apply_widened,
    load_times,
    widened,
)
from book_guard._sessions import (
    NEEDS_CHECK,
    NEEDS_QUIZ,
    Session,
    build_sessions,
    open_start,
)

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard._ledger import Entry, Ledger
    from book_guard._paths import Paths
    from book_guard._photos import PhotoRecord

CREDITED = "credited"


@dataclass(frozen=True)
class SessionView:
    """A session and its status (a ledger credit wins over the protocol).

    A failed summary keeps the protocol's status (``needs-quiz``) until a
    rewrite passes: every surface that asks for a summary asks again, as
    many times as it takes.
    """

    session: Session
    book: Book | None
    status: str
    verdicts: tuple[Entry, ...] = ()

    @property
    def last_verdict(self) -> Entry | None:
        """The newest credit/reject row, if the summary was graded at all."""
        return self.verdicts[-1] if self.verdicts else None


@dataclass(frozen=True)
class Snapshot:
    """Everything any surface needs, derived once."""

    today: date
    book: Book | None
    sessions: list[SessionView]
    open_start: PhotoRecord | None
    pace: Pace
    sick_days: frozenset[date]
    """The sick days book-guard stands down on (:func:`_sick.standing_down`:
    a sick day that keeps ``book`` is not one), as read for this snapshot."""
    escaped_today: bool
    escapes_left: int
    locked: bool
    reason: str

    @property
    def sick_today(self) -> bool:
        """Today is a sick day: the gate stands down and today asks nothing."""
        return self.today in self.sick_days

    def with_status(self, *statuses: str) -> list[SessionView]:
        """Sessions currently in any of ``statuses``."""
        return [s for s in self.sessions if s.status in statuses]


def _session_views(
    ledger: Ledger, records: dict[str, PhotoRecord], times: SessionTimes
) -> list[SessionView]:
    verdicts = ledger.verdicts()
    signed = widened(ledger)
    views = []
    for session in build_sessions(_photos.usable_pages(records)):
        apply_times(session, times)
        apply_widened(session, signed)
        found = verdicts.get(session.session_id, [])
        status = session.state
        if credited(found):
            status = CREDITED
        book = book_at(ledger, session.end.taken)
        views.append(SessionView(session, book, status, tuple(found)))
    return views


def _verdict(
    today: date, pace: Pace, *, sick: bool, free: bool, escaped: bool
) -> tuple[bool, str]:
    if today < GATE_START_DATE:
        return False, f"book-guard starts on {GATE_START_DATE}"
    if sick:
        # First, so the reason names it even when on pace: the gate stands
        # down for the whole day; its share moves to the days left (_resplit).
        return False, "today is a sick day"
    if not pace.behind:
        # Reading caught up: that is the reason it is open, whatever else
        # happened today (an escape used this morning no longer matters).
        return False, "on pace"
    if pace.passed_today:
        # Reading anything beats reading nothing: a 20-page day opens the
        # lock while the debt stays, spread over the days left.
        return False, (
            f"{pace.pages_today} pages read today "
            f"(still {pace.behind} behind the pace line)"
        )
    excuse = (
        "today is a free day"
        if free
        else "today's lock was skipped with the escape hatch"
        if escaped
        else None
    )
    if excuse is not None:
        return False, excuse
    short = DAILY_PASS_PAGES - pace.pages_today
    return True, (
        f"{pace.behind} pages behind the pace line; {short} more "
        f"{'page' if short == 1 else 'pages'} read today open it"
    )


@dataclass(frozen=True)
class _Calendar:
    """Which days are free and which stand down sick."""

    is_free: Callable[[date], bool]
    sick: frozenset[date]


def _decide(
    ledger: _ledger.Ledger, day: date, pace: Pace, cal: _Calendar, *, escaped: bool
) -> tuple[bool, str]:
    """Locked or not, and why: the one-number rule from the resplit."""
    flags = {"sick": day in cal.sick, "free": cal.is_free(day), "escaped": escaped}
    if day < RESPLIT_DATE:
        return _verdict(day, pace, **flags)
    yesterday = day - timedelta(days=1)
    kept_yesterday = kept(ledger, yesterday, cal.is_free, sick=cal.sick)
    return one_number(pace, kept_yesterday=kept_yesterday, **flags)


def snapshot(
    paths: Paths,
    *,
    today: date | None = None,
    is_free: Callable[[date], bool] | None = None,
    sick: frozenset[date] | None = None,
) -> Snapshot:
    """Read the ledger and photo cache and derive the full state.

    ``sick`` defaults to the shared pool's days that do not keep ``book``
    (:func:`_sick.standing_down`), which reads as no sick day at all when it
    is unreadable: the gate fails closed.

    Raises:
        ValueError: The ledger or photo cache is corrupt.
    """
    day = today or datetime.now().astimezone().date()
    free_check = is_free or freedays.is_free_day
    sick_days = _sick.standing_down() if sick is None else sick
    ledger = _ledger.load(paths.ledger, paths.key_file)
    records = _photos.load(paths.photos)
    pace = compute_pace(ledger, day, free_check, sick=sick_days)
    month = day.isoformat()[:7]
    escapes = [e for e in ledger.of_kind(ESCAPE) if e.day.startswith(month)]
    escaped = any(e.day == day.isoformat() for e in escapes)
    locked, reason = _decide(
        ledger, day, pace, _Calendar(free_check, sick_days), escaped=escaped
    )
    return Snapshot(
        today=day,
        book=current(ledger),
        sessions=_session_views(ledger, records, load_times(paths.session_times)),
        open_start=open_start(_photos.usable_pages(records)),
        pace=pace,
        sick_days=sick_days,
        escaped_today=escaped,
        escapes_left=max(0, ESCAPES_PER_MONTH - len(escapes)),
        locked=locked,
        reason=reason,
    )


def awaiting_quiz(snap: Snapshot) -> list[SessionView]:
    """Sessions whose summary is the only thing missing."""
    return snap.with_status(NEEDS_QUIZ)


def awaiting_check(snap: Snapshot) -> list[SessionView]:
    """Sessions waiting for their check-page photo."""
    return snap.with_status(NEEDS_CHECK)
