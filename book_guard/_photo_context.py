# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What an inbox photo was taken for, and what the phone said about it.

The app names every upload after its button -- ``start_``, ``stop_``,
``check<N>_`` -- and may drop a sidecar ``<photo>.json`` *before* the photo:

    {"page": 51, "box": [left, top, right, bottom]}

``page`` is what the phone's own OCR read (and the reader confirmed): it is
the page, taken as is -- the PC does not re-read or second-guess it. ``box``
is where the number is, in the stored file's pixels (before EXIF), from the
phone's OCR or drawn by hand: with no ``page``, the PC reads that box
itself.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import logging
import re
from typing import TYPE_CHECKING, Final

from book_guard._books import book_at
from book_guard._pagenum import Box, Context
from book_guard._photos import usable_pages
from book_guard._sessions import build_sessions, open_start

if TYPE_CHECKING:
    from collections.abc import Sequence
    from datetime import datetime
    from pathlib import Path

    from book_guard._ledger import Ledger
    from book_guard._photos import PhotoRecord
    from book_guard._sessions import Session

_logger: Final = logging.getLogger(__name__)

_LABEL: Final = re.compile(r"^(start|stop|check(\d+))_")
_BOX_LEN: Final = 4
SIDECAR_SUFFIX: Final = ".json"


@dataclass(frozen=True)
class Sidecar:
    """The phone's note on one photo; empty when there is none."""

    hint: int | None = None
    box: Box | None = None


def sidecar_path(photo: Path) -> Path:
    """Where the phone puts ``photo``'s note."""
    return photo.with_name(photo.name + SIDECAR_SUFFIX)


def parse_box(raw: object) -> Box | None:
    """A ``[left, top, right, bottom]`` list of ints, or ``None``."""
    if not isinstance(raw, list) or len(raw) != _BOX_LEN:
        return None
    if not all(isinstance(v, int) and not isinstance(v, bool) for v in raw):
        return None
    left, top, right, bottom = raw
    return (left, top, right, bottom) if right > left and bottom > top else None


def read_sidecar(photo: Path) -> Sidecar:
    """``photo``'s note, or an empty one (missing, or not the expected shape)."""
    note = sidecar_path(photo)
    if not note.exists():
        return Sidecar()
    try:
        raw = json.loads(note.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _logger.warning("ignoring unreadable sidecar for %s (%s)", photo.name, exc)
        return Sidecar()
    if not isinstance(raw, dict):
        return Sidecar()
    hint = raw.get("page")
    valid_hint = hint if isinstance(hint, int) and not isinstance(hint, bool) else None
    return Sidecar(hint=valid_hint, box=parse_box(raw.get("box")))


def context_for(
    name: str,
    taken: datetime,
    records: dict[str, PhotoRecord],
    ledger: Ledger,
    app: Sequence[Session] = (),
) -> Context:
    """What the page number of photo ``name`` (taken at ``taken``) must fit.

    ``app`` are the sessions read in the app: a start photo after one is
    near where it stopped (an estimate, but the nearest there is).
    """
    book = book_at(ledger, taken)
    last_page = book.pages if book else None
    label = _LABEL.match(name)
    if label is None:
        return Context(last_page=last_page)
    if label.group(2):
        return Context(expected=int(label.group(2)), last_page=last_page)
    pages = usable_pages(records)
    breaks = [s.start.taken for s in app]
    if label.group(1) == "stop":
        start = open_start(pages, breaks)
        return Context(after=start.page if start else None, last_page=last_page)
    # Where the last session ended -- not the last photo: the check photo
    # (p. 19 of a p. 7-51 session) is taken after the stop photo.
    isbn = book.isbn if book else None
    ends = [
        s.end
        for s in build_sessions(pages, breaks)
        if s.end.taken <= taken
        and (b := book_at(ledger, s.end.taken))
        and b.isbn == isbn
    ]
    ends += [
        s.end
        for s in app
        if s.ebook is not None and s.ebook.isbn == isbn and s.end.taken <= taken
    ]
    last = max(ends, key=lambda e: e.taken, default=None)
    return Context(near=last.page if last else None, last_page=last_page)
