# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What a photo shows, read entirely on this PC -- no model, no network.

1. A barcode zbar can decode is an ISBN photo.
2. Otherwise Tesseract turns the page upright by its content and reads it;
   :mod:`book_guard._pagenum` picks the printed page number from what the
   photo was taken for.
3. A page whose number cannot be pinned down carries the reason, so the
   app can ask for the number to be boxed instead of the photo vanishing.
"""

from __future__ import annotations

import logging
import re
from typing import TYPE_CHECKING, Final

from PIL import Image

from book_guard._ocr import barcode_isbn, scan
from book_guard._pagenum import (
    Box,
    Context,
    candidates,
    choose,
    read_box,
    upright_box,
)
from book_guard._vision import ISBN, OTHER, PAGE, Reading, normalise_isbn

if TYPE_CHECKING:
    from pathlib import Path

_logger: Final = logging.getLogger(__name__)

MIN_LOCAL_TEXT: Final = 200
"""Below this (and no number) it is a cover, a blank or a dark shot, not a page."""
_PRINTED_ISBN: Final = re.compile(r"ISBN[\s:]*([\dX][\d\s-]{8,16}[\dX])", re.IGNORECASE)
_ISBN13_LEN: Final = 13
_ASK_FOR_BOX: Final = " -- box the page number in the app, or retake the photo"


def _printed_isbn(text: str) -> str | None:
    for match in _PRINTED_ISBN.finditer(text):
        isbn = normalise_isbn(match.group(1))
        if isbn and len(isbn) == _ISBN13_LEN:
            return isbn
    return None


def read(path: Path, context: Context, box: Box | None = None) -> Reading:
    """Read one photo.

    ``box`` is where the page number is, in the stored file's pixels (before
    EXIF) -- drawn on the phone or found by its OCR. The PC reads that box
    itself; if nothing is legible there, the whole page decides as usual.
    """
    isbn = barcode_isbn(path)
    if isbn is not None:
        return Reading(kind=ISBN, page_number=None, isbn=isbn, text="")
    page = scan(path)
    if page is None:
        return Reading(OTHER, None, None, "", reason="the PC could not read the photo")
    found: list[int] = []
    if box is not None:
        with Image.open(path) as stored:
            turned = upright_box(stored, box, page.rotation)
        found = read_box(page.image, turned) if turned else []
        if found and context.hint is not None and found != [context.hint]:
            # The two readers disagree on the same box: trust neither alone
            # (a misread "108" for 103 on a stop is extra credit).
            _logger.warning(
                "%s: box reads %s, the phone read %s", path.name, found, context.hint
            )
            found = []
    boxed = bool(found)
    if not boxed:  # no box, nothing legible, or disputed: the whole page decides
        found = candidates(page)
    choice = choose(found, context, boxed=boxed)
    if choice.page is not None:
        return Reading(PAGE, choice.page, None, page.text, rotation=page.rotation)
    printed = _printed_isbn(page.text)
    if printed is not None:
        return Reading(ISBN, None, printed, "", rotation=page.rotation)
    if not found and len(page.text) < MIN_LOCAL_TEXT:
        return Reading(
            OTHER, None, None, "", reason="no page on the photo", rotation=page.rotation
        )
    return Reading(
        OTHER,
        None,
        None,
        page.text,
        reason=choice.reason + _ASK_FOR_BOX,
        rotation=page.rotation,
    )
