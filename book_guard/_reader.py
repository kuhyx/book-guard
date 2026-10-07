# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What a photo shows, read entirely on this PC -- no model, no network.

0. A page number the phone read (ML Kit, sidecar note) is the page: the PC
   only transcribes the text for the grader. No re-read, no plausibility
   check, no "unclear" -- the reader already saw and confirmed it.
1. Otherwise a barcode zbar can decode is an ISBN photo.
2. Otherwise Tesseract turns the page upright by its content and reads it;
   :mod:`book_guard._pagenum` picks the printed page number from what the
   photo was taken for. This is the fallback for photos with no phone
   reading (the desktop web app has no OCR).
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

    from book_guard._ocr import Scan

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


def _box_numbers(path: Path, page: Scan, box: Box, context: Context) -> list[int]:
    """What the PC makes of the boxed number -- [] when it settles nothing."""
    with Image.open(path) as stored:
        turned = upright_box(stored, box, page.rotation)
    found = read_box(page.image, turned) if turned else []
    if context.expected is None:
        return found[:1]  # no second opinion: the most frequent reading
    return found


def _phone_page(path: Path, page_number: int) -> Reading:
    """The phone's number, taken as is; the PC adds only the transcription.

    The text still matters -- it is the grader's evidence and what anchors
    the photo in an attached book file -- but nothing here can overrule
    the number.
    """
    page = scan(path)
    if page is None:
        _logger.warning("%s: no text; phone's p. %s kept", path.name, page_number)
        return Reading(PAGE, page_number, None, "")
    return Reading(PAGE, page_number, None, page.text, rotation=page.rotation)


def read(path: Path, context: Context, box: Box | None = None) -> Reading:
    """Read one photo.

    ``context.hint`` is the page number the phone read: when there is one,
    it is the page (:func:`_phone_page`). Otherwise ``box`` is where the
    page number is, in the stored file's pixels (before EXIF) -- drawn on
    the phone. The PC reads that box itself; if nothing is legible there,
    the whole page decides as usual.
    """
    if context.hint is not None:
        return _phone_page(path, context.hint)
    return _pc_reading(path, context, box)


def _pc_reading(path: Path, context: Context, box: Box | None) -> Reading:
    """The fallback: no number from the phone, so the PC finds one itself."""
    isbn = barcode_isbn(path)
    if isbn is not None:
        return Reading(kind=ISBN, page_number=None, isbn=isbn, text="")
    page = scan(path)
    if page is None:
        return Reading(OTHER, None, None, "", reason="the PC could not read the photo")
    found = _box_numbers(path, page, box, context) if box is not None else []
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
