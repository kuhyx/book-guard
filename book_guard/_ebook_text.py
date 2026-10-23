# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The ebook text the in-app reader serves, and where its story is.

Split from :mod:`book_guard._ebook_map`: what the app is sent (offsets
shared with the PC) and which part of it is the story, not front or back
matter -- the page map's two end knots.
"""

from __future__ import annotations

import re
from typing import Final

MIN_PARAGRAPH: Final = 200
"""The story starts at the first paragraph this long (front matter is short)."""
BACK_MATTER_SHARE: Final = 0.1
"""Back matter (editor's notes, licence) is looked for in the last tenth."""
_PARAGRAPH: Final = re.compile(r"[^\n]*\S[^\n]*(?:\n[^\n]*\S[^\n]*)*")
_THE_END: Final = re.compile(
    r"(?:THE END|The End|END|KONIEC|Koniec|FIN|Fin)\W*", re.UNICODE
)
_FOOTNOTE: Final = "↑"  # "↑": Wikisource's back-link before each note
_ASTRAL: Final = re.compile("[\U00010000-\U0010ffff]")


def served_text(text: str) -> str:
    """``text`` as the app gets it: astral characters become U+FFFD.

    One code point for one, so every offset is unchanged -- and Dart, which
    indexes UTF-16 units, then counts exactly what Python counts.
    """
    return _ASTRAL.sub("�", text)


def story_bounds(text: str) -> tuple[int, int]:
    """``(start, end)`` of the story: front and back matter left out.

    The start is the first paragraph of :data:`MIN_PARAGRAPH`+ characters
    (title pages, imprints and headings are short). The end is the last
    paragraph before the back matter -- a closing "THE END"/"KONIEC" or a
    Wikisource ``↑`` footnote list -- found in the last tenth of the text.
    """
    paragraphs = [(m.start(), m.end()) for m in _PARAGRAPH.finditer(text)]
    start = next((a for a, b in paragraphs if b - a >= MIN_PARAGRAPH), 0)
    tail = len(text) * (1 - BACK_MATTER_SHARE)
    marker = next(
        (
            a
            for a, b in paragraphs
            if a >= tail
            and (text[a] == _FOOTNOTE or _THE_END.fullmatch(text[a:b].strip()))
        ),
        None,
    )
    ends = [b for _, b in paragraphs if marker is None or b <= marker]
    return start, (ends[-1] if ends else 0)
