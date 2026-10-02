# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A photo of the table of contents -> the book's chapters.

The app uploads such photos as ``toc-*.jpg`` from a separate button, so they
are never guessed at. The model transcribes the page as ``title page`` lines
and :func:`parse_toc` reads every line ending in a page number.

Not Tesseract, measured (2026-10-02): even on a cleanly rendered contents
page it dropped whole entries without a trace ("Wstęp" vanished) and read
page numbers as "2D" / "B1" through the dot leaders. A missing chapter
cannot be detected afterwards, and this runs about once per book, so one
model call is the right price.
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING, Final

from book_guard._books import Chapter, normalise_chapters
from book_guard._claude import DEFAULT_MODEL, ask

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

TOC_PREFIX: Final = "toc-"
_LEADER: Final = re.compile(r"\s*[.·…_]{3,}|\s*(?:\. ){3,}")
_LINE: Final = re.compile(
    r"^\s*(?P<title>.*?[^\W\d_].*?)[\s.·…_\-\u2013—]*?(?P<page>\d{1,4})\s*$"
)
_MIN_LETTERS: Final = 3

_SYSTEM: Final = "You transcribe tables of contents of printed books."
_PROMPT: Final = """This photo shows a book's table of contents. Answer with
the line {"kind": "toc"}, then a line containing only ---TEXT---, then one
line per entry exactly as printed: the title, a space, the page number.
Copy titles verbatim; skip entries without a page number.
"""


def parse_toc(text: str) -> tuple[Chapter, ...]:
    """Every line that ends in a page number, as (start page, title)."""
    rows: list[list[object]] = []
    for line in text.splitlines():
        match = _LINE.match(line)
        if match is None:
            continue
        title = _LEADER.split(match.group("title"))[0].strip(" .·…_-\u2013—\t")
        if sum(ch.isalpha() for ch in title) >= _MIN_LETTERS:
            rows.append([int(match.group("page")), title])
    return normalise_chapters(rows)


def transcribe(jpeg_b64: str, *, model: str = DEFAULT_MODEL) -> str:
    """The model's ``title page`` transcription of a contents page."""
    return str(ask(_SYSTEM, _PROMPT, [jpeg_b64], model=model).get("text") or "")


def read_toc(
    _path: Path, jpeg_b64: str, *, model_text: Callable[[str], str] = transcribe
) -> tuple[Chapter, ...]:
    """The chapters on one contents photo. Raises ``ClaudeUnavailableError``."""
    return parse_toc(model_text(jpeg_b64))
