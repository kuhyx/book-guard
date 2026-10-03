# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Pair page photos into reading sessions. Pure: records in, sessions out.

The protocol the phone side follows:

1. Photograph the open page when you start reading.
2. Photograph the open page when you stop.
3. Photograph the *check page* book-guard then names (in NEXT.txt) --
   a page between the two, picked from the photos' hashes, so it cannot be
   known before the end photo exists.

Walking the photos in capture order:

* a photo showing a pending session's check page, taken after that session
  ended, is that session's check photo;
* otherwise it closes the open session if it shows a later page within
  :data:`MAX_SESSION` of the start;
* otherwise it opens a new session (a stale or backwards start is replaced).

Everything is re-derived from the photo cache on every run, so there is no
session state to go stale -- only the ledger's credit/reject verdicts.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
from typing import TYPE_CHECKING, Final

from book_guard._constants import MAX_SESSION, MIN_SECONDS_PER_PAGE

if TYPE_CHECKING:
    from datetime import datetime

    from book_guard._photos import PhotoRecord

TOO_FAST: Final = "too-fast"
NEEDS_CHECK: Final = "needs-check-photo"
NEEDS_QUIZ: Final = "needs-quiz"


@dataclass
class Session:
    """A start/end photo pair and, once taken, its check photo."""

    start: PhotoRecord
    end: PhotoRecord
    check_page: int | None
    check: PhotoRecord | None = None
    started: datetime | None = None
    """A later start the reader set (``_session_times``); never earlier."""
    ended: datetime | None = None
    """An earlier end the reader set; never later."""

    @property
    def started_at(self) -> datetime:
        """When reading began: the start photo, or the reader's later time."""
        return self.started or self.start.taken

    @property
    def ended_at(self) -> datetime:
        """When reading ended: the end photo, or the reader's earlier time."""
        return self.ended or self.end.taken

    @property
    def session_id(self) -> str:
        """Stable ledger id: the two photos' hashes."""
        return f"session:{self.start.sha[:16]}-{self.end.sha[:16]}"

    @property
    def pages(self) -> int:
        """Pages read: start page up to (not including) the end page."""
        return int(self.end.page or 0) - int(self.start.page or 0)

    @property
    def seconds(self) -> float:
        """Time read: the photos' span, narrowed by any time the reader set."""
        return (self.ended_at - self.started_at).total_seconds()

    @property
    def minutes(self) -> int:
        """Whole minutes read."""
        return int(self.seconds // 60)

    @property
    def state(self) -> str:
        """Where the session is in the protocol, before any ledger verdict."""
        if self.seconds < self.pages * MIN_SECONDS_PER_PAGE:
            return TOO_FAST
        if self.check_page is not None and self.check is None:
            return NEEDS_CHECK
        return NEEDS_QUIZ

    @property
    def evidence(self) -> list[PhotoRecord]:
        """The photos whose transcribed text the grader sees."""
        return [p for p in (self.start, self.check, self.end) if p is not None]


def check_page_for(start: PhotoRecord, end: PhotoRecord) -> int | None:
    """The page to photograph as proof, strictly between start and end.

    ``None`` when there is no page strictly between (a 1-page session) --
    both of its pages are already photographed.
    """
    low, high = int(start.page or 0) + 1, int(end.page or 0) - 1
    if high < low:
        return None
    seed = hashlib.sha256((start.sha + end.sha).encode()).digest()
    return low + int.from_bytes(seed[:8], "big") % (high - low + 1)


def _claims_check(pending: list[Session], photo: PhotoRecord) -> bool:
    """Attach ``photo`` as the check photo of the first session it answers."""
    for session in pending:
        if session.check_page == photo.page and photo.taken > session.end.taken:
            session.check = photo
            pending.remove(session)
            return True
    return False


def build_sessions(pages: list[PhotoRecord]) -> list[Session]:
    """Every session the page photos form, oldest first.

    Args:
        pages: Accepted page photos in capture order
            (:func:`book_guard._photos.usable_pages`).
    """
    sessions: list[Session] = []
    pending: list[Session] = []
    start: PhotoRecord | None = None
    for photo in pages:
        if _claims_check(pending, photo):
            continue
        if (
            start is None
            or int(photo.page or 0) <= int(start.page or 0)
            or photo.taken - start.taken > MAX_SESSION
        ):
            start = photo
            continue
        session = Session(start, photo, check_page_for(start, photo))
        sessions.append(session)
        if session.check_page is not None:
            pending.append(session)
        start = None
    return sessions


def open_start(pages: list[PhotoRecord]) -> PhotoRecord | None:
    """The start photo still waiting for its end photo, if any."""
    consumed = {
        p.sha for s in build_sessions(pages) for p in (s.start, s.end, s.check) if p
    }
    rest = [p for p in pages if p.sha not in consumed]
    if not rest or not pages or rest[-1].sha != pages[-1].sha:
        return None
    return rest[-1]
