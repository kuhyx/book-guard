# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Signed manual starts as page records the session builder pairs.

A ``start:`` ledger row (written only by ``book-guard start``,
:mod:`book_guard._manual_start`) stands in for a start photo the app could
not take. :func:`pages` is every caller's input to the session builder:
the accepted photos plus one text-less record per manual start, so the
gate, the photo context, the ebook overlap and the lock all see one start.

A real photo of the same page taken next (within :data:`MAX_SESSION`)
replaces it: the photo's EXIF time becomes the clock. The PC stores no
start/stop label, so a same-page photo never closes a manual start.
"""

from __future__ import annotations

import hashlib
from typing import TYPE_CHECKING, Final

from book_guard._constants import MAX_SESSION
from book_guard._errlog import log_error
from book_guard._photos import MANUAL_START_NAME, OK, PhotoRecord, usable_pages

if TYPE_CHECKING:
    from book_guard._ledger import Entry, Ledger
    from book_guard._paths import Paths

KIND: Final = "start"
PREFIX: Final = "start:"


def record_of(entry: Entry) -> PhotoRecord:
    """The page record a ``start:`` row stands for."""
    at = entry.detail["at"]
    return PhotoRecord(
        sha=hashlib.sha256(entry.entry_id.encode()).hexdigest(),
        name=MANUAL_START_NAME,
        taken_at=at,
        uploaded_at=at,
        kind="page",
        page=int(entry.detail["page"]),
        status=OK,
    )


def _replacement(manual: PhotoRecord, real: list[PhotoRecord]) -> PhotoRecord | None:
    """The real photo that replaces ``manual``, if the next one is its page."""
    nxt = next((p for p in real if p.taken > manual.taken), None)
    if (
        nxt is not None
        and nxt.page == manual.page
        and nxt.taken - manual.taken <= MAX_SESSION
    ):
        return nxt
    return None


def pages(ledger: Ledger, records: dict[str, PhotoRecord]) -> list[PhotoRecord]:
    """Accepted page photos plus the unreplaced manual starts, by capture time."""
    real = usable_pages(records)
    manual = [record_of(e) for e in ledger.of_kind(KIND)]
    kept = [m for m in manual if _replacement(m, real) is None]
    return sorted([*real, *kept], key=lambda r: (r.taken, r.sha))


def replaced_by(
    ledger: Ledger, records: dict[str, PhotoRecord], sha: str
) -> Entry | None:
    """The manual start the photo ``sha`` replaced, if any."""
    real = usable_pages(records)
    for entry in ledger.of_kind(KIND):
        found = _replacement(record_of(entry), real)
        if found is not None and found.sha == sha:
            return entry
    return None


def log_replacement(
    paths: Paths, ledger: Ledger, records: dict[str, PhotoRecord], record: PhotoRecord
) -> None:
    """Log once (the photo is read once) that ``record`` replaced a manual start."""
    entry = replaced_by(ledger, records, record.sha)
    if entry is not None:
        log_error(
            paths,
            "start",
            "manual start replaced",
            start=entry.entry_id,
            photo=record.sha,
            at=entry.detail["at"],
        )
