# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Classify one inbox photo: the phone's number, a barcode, or ``needs number``.

Split from :mod:`book_guard._inbox` (which walks the inbox and files photos).
The page number is the phone's (its sidecar note), taken as is; the PC reads
none. See that module for the whole rule.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from typing import TYPE_CHECKING

from book_guard import _page_truth
from book_guard._constants import MAX_UPLOAD_DELAY
from book_guard._photo_context import context_for, read_sidecar
from book_guard._photos import (
    KEPT,
    KEPT_PREFIX,
    NEEDS_NUMBER,
    OK,
    REJECTED,
    PhotoRecord,
)
from book_guard._vision import ISBN

if TYPE_CHECKING:
    from collections.abc import Callable
    from datetime import datetime
    from pathlib import Path

    from book_guard._books import Chapter
    from book_guard._ledger import Ledger
    from book_guard._pagenum import Context
    from book_guard._paths import Paths
    from book_guard._photo import PhotoFile
    from book_guard._sessions import Session
    from book_guard._vision import Reading

    Reader = Callable[[Path, Context], Reading]
    BarcodeReader = Callable[[Path], str | None]


@dataclass(frozen=True)
class Pass:
    """What one inbox pass classifies a photo against, and reads it with."""

    paths: Paths
    reader: Reader
    barcode: BarcodeReader
    records: dict[str, PhotoRecord]
    ledger: Ledger
    app: list[Session]


def rejected(
    photo: PhotoFile, path: Path, uploaded: datetime, reason: str
) -> PhotoRecord:
    """``photo`` as a rejected ``other``, with the ``reason`` the app shows."""
    taken = photo.taken_at.isoformat() if photo.taken_at else ""
    return PhotoRecord(
        sha=photo.sha,
        name=path.name,
        taken_at=taken,
        uploaded_at=uploaded.isoformat(),
        kind="other",
        status=REJECTED,
        reason=reason,
    )


def contents_record(
    photo: PhotoFile, path: Path, uploaded: datetime, chapters: tuple[Chapter, ...]
) -> PhotoRecord:
    """A contents photo: not session evidence, so no clock checks."""
    return PhotoRecord(
        sha=photo.sha,
        name=path.name,
        taken_at=photo.taken_at.isoformat() if photo.taken_at else "",
        uploaded_at=uploaded.isoformat(),
        kind="toc",
        text="\n".join(f"{c.start}\t{c.title}" for c in chapters),
    )


def _isbn_or_needs_number(
    photo: PhotoFile, path: Path, uploaded: datetime, barcode: BarcodeReader
) -> PhotoRecord:
    """A photo with no number from the phone: an ISBN photo, else ``needs number``."""
    isbn = barcode(path)
    if isbn is None:
        return rejected(photo, path, uploaded, NEEDS_NUMBER)
    return PhotoRecord(
        sha=photo.sha,
        name=path.name,
        taken_at=photo.taken_at.isoformat() if photo.taken_at else "",
        uploaded_at=uploaded.isoformat(),
        kind=ISBN,
        isbn=isbn,
    )


def classify(
    photo: PhotoFile, path: Path, uploaded: datetime, known: Pass
) -> tuple[PhotoRecord, int]:
    """Classify one photo against the pass's photo cache, ledger and app sessions.

    Returns the record and the turn that makes it upright (for the thumb).
    """
    if photo.taken_at is None:
        return rejected(photo, path, uploaded, "no EXIF capture time"), 0
    kept = path.name.startswith(KEPT_PREFIX)
    if uploaded - photo.taken_at > MAX_UPLOAD_DELAY and not kept:
        reason = "uploaded more than 7 days after it was taken"
        return rejected(photo, path, uploaded, reason), 0
    note = read_sidecar(path)
    if note.hint is None:
        return _isbn_or_needs_number(photo, path, uploaded, known.barcode), 0
    context = replace(
        context_for(path.name, photo.taken_at, known.records, known.ledger, known.app),
        hint=note.hint,
    )
    _page_truth.note_ocr_miss(known.paths, path, photo.sha, context, note)
    reading = known.reader(path, context)
    record = PhotoRecord(
        sha=photo.sha,
        name=path.name,
        taken_at=photo.taken_at.isoformat(),
        uploaded_at=uploaded.isoformat(),
        kind=reading.kind,
        page=reading.page_number,
        isbn=reading.isbn,
        text=reading.text,
        status=REJECTED if reading.reason else OK,
        reason=reading.reason,
        pencil_page=reading.pencil_page,
    )
    if kept and record.kind == "page":
        # Never session evidence, so its age does not matter either.
        record = replace(record, kind=KEPT)
    return record, reading.rotation
