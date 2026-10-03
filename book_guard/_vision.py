# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What a photo shows: a book page (number + text), a barcode, or neither.

Photos are read locally (:mod:`book_guard._reader`); no model is asked.
Until 2026-10-03 Haiku read every page number, which tied each photo to a
working Claude login with usage left -- a photo of p. 51 sat in the inbox
for half an hour on "claude exited 1", then was misread as 19.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Final

PAGE: Final = "page"
ISBN: Final = "isbn"
OTHER: Final = "other"

_ISBN_CHARS: Final = re.compile(r"[^0-9Xx]")


@dataclass(frozen=True)
class Reading:
    """One photo, read."""

    kind: str
    page_number: int | None
    isbn: str | None
    text: str
    reason: str = ""
    """Why a photo meant as a page has no page number; "" otherwise."""
    rotation: int = 0
    """Degrees counter-clockwise, after EXIF, that make the page upright."""


def normalise_isbn(raw: object) -> str | None:
    """Digits (and a final X) only, or ``None`` if it cannot be an ISBN."""
    cleaned = _ISBN_CHARS.sub("", str(raw or "")).upper()
    return cleaned if len(cleaned) in {10, 13} else None
