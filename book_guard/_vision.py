# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What a photo shows: a book page (number + text), a barcode, or neither."""

from __future__ import annotations

from dataclasses import dataclass
import logging
import re
from typing import Final

from book_guard._claude import DEFAULT_MODEL, ask

_logger: Final = logging.getLogger(__name__)

PAGE: Final = "page"
ISBN: Final = "isbn"
OTHER: Final = "other"

_SYSTEM: Final = (
    "You read photos of printed paper books for a reading tracker. You answer "
    "with one JSON object and nothing else."
)

_PROMPT: Final = """Classify this photo and extract data. Answer with ONE line
of JSON, then a line containing only ---TEXT---, then the text:
{"kind": "page" | "isbn" | "other",
 "page_number": <int or null>, "isbn": <string or null>}
---TEXT---
<text>

- "page": an open book page. page_number = the PRINTED page number of the
  page that is most fully in view (for a two-page spread, the LOWER number of
  the pair). null if no page number is legible -- never guess one.
  The text = a verbatim transcription of the readable body text, up to ~1500
  characters, preserving the wording exactly.
- "isbn": a back cover, copyright page or barcode showing an ISBN. isbn = the
  digits (hyphens removed). The text = the title/author if visible.
- "other": anything else; the text is empty.
"""

_ISBN_CHARS: Final = re.compile(r"[^0-9Xx]")


@dataclass(frozen=True)
class Reading:
    """The model's reading of one photo, normalised and type-checked."""

    kind: str
    page_number: int | None
    isbn: str | None
    text: str


def normalise_isbn(raw: object) -> str | None:
    """Digits (and a final X) only, or ``None`` if it cannot be an ISBN."""
    cleaned = _ISBN_CHARS.sub("", str(raw or "")).upper()
    return cleaned if len(cleaned) in {10, 13} else None


def _page_number(raw: object) -> int | None:
    if isinstance(raw, bool) or not isinstance(raw, int | str):
        return None
    try:
        value = int(raw)
    except ValueError:
        _logger.warning("model gave a non-numeric page number %r", raw)
        return None
    return value if value > 0 else None


def from_answer(answer: dict[str, object]) -> Reading:
    """Turn the model's JSON into a :class:`Reading`, trusting nothing."""
    kind = str(answer.get("kind", OTHER))
    if kind not in {PAGE, ISBN, OTHER}:
        kind = OTHER
    page = _page_number(answer.get("page_number")) if kind == PAGE else None
    isbn = normalise_isbn(answer.get("isbn")) if kind == ISBN else None
    if (kind == PAGE and page is None) or (kind == ISBN and isbn is None):
        kind = OTHER
    return Reading(
        kind=kind, page_number=page, isbn=isbn, text=str(answer.get("text") or "")
    )


def read_photo(jpeg_b64: str, *, model: str = DEFAULT_MODEL) -> Reading:
    """Ask the model what the photo shows.

    Raises:
        ClaudeUnavailableError: Propagated -- a photo that could not be read
            stays in the inbox and is retried, it is never filed as "other".
    """
    return from_answer(ask(_SYSTEM, _PROMPT, [jpeg_b64], model=model))


_NUMBER_PROMPT: Final = """Classify this photo. Answer with ONE line of JSON
and nothing else:
{"kind": "page" | "isbn" | "other",
 "page_number": <int or null>, "isbn": <string or null>}

- "page": an open book page. page_number = the PRINTED page number of the
  page that is most fully in view (for a two-page spread, the LOWER number of
  the pair). null if no page number is legible -- never guess one.
- "isbn": a back cover, copyright page or barcode showing an ISBN; isbn = the
  digits (hyphens removed).
- "other": anything else.
"""


def read_page_number(jpeg_b64: str, *, model: str = DEFAULT_MODEL) -> Reading:
    """Ask only what the photo is and its page number -- no transcription.

    Used when Tesseract already has the text: the answer is a few tokens
    instead of ~1500 characters, and the text cannot be hallucinated.
    """
    return from_answer(ask(_SYSTEM, _NUMBER_PROMPT, [jpeg_b64], model=model))
