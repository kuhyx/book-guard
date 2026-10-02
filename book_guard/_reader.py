# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What a photo shows: local tools first, the model only for what they miss.

1. A barcode zbar can decode is an ISBN photo -- no model call at all.
2. Text Tesseract can read (:data:`MIN_LOCAL_TEXT` or more) is kept as the
   transcription; the model is asked only for the kind and printed page
   number (:func:`~book_guard._vision.read_page_number`), a few tokens.
3. Otherwise the model reads everything, as before.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Final

from book_guard._ocr import barcode_isbn, page_text
from book_guard._vision import ISBN, PAGE, Reading, read_page_number, read_photo

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

MIN_LOCAL_TEXT: Final = 200
"""Below this Tesseract probably saw a cover or a blurry shot, not a page."""


def read(
    path: Path,
    jpeg_b64: str,
    *,
    full: Callable[[str], Reading] = read_photo,
    number: Callable[[str], Reading] = read_page_number,
) -> Reading:
    """Read one photo. Raises ``ClaudeUnavailableError`` from the model."""
    isbn = barcode_isbn(path)
    if isbn is not None:
        return Reading(kind=ISBN, page_number=None, isbn=isbn, text="")
    text = page_text(path)
    if len(text) < MIN_LOCAL_TEXT:
        return full(jpeg_b64)
    answer = number(jpeg_b64)
    return Reading(
        kind=answer.kind,
        page_number=answer.page_number,
        isbn=answer.isbn,
        text=text if answer.kind == PAGE else "",
    )
