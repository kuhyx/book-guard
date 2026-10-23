# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A synthetic ebook and its photographed pages, for the in-app reading tests.

Each page is ~1500 characters of words drawn from a random vocabulary
seeded by the page number, so every page reads differently and a page's
"photo" (its words with some lost, as OCR loses them) locates in the text.
Seeded numpy generators: the same text on every run.
"""

from __future__ import annotations

from typing import Final

import numpy as np

PAGE_CHARS: Final = 1500
FRONT: Final = (
    "Title\n\nAuthor\n\nPublisher, 1928\n\n* * *\n\nPART ONE\n\nCHAPTER I\n\n"
)
_LETTERS: Final = "abcdefghijklmnoprstuwyz"


def vocabulary(seed: int, size: int = 4000) -> list[str]:
    """``size`` random 6-9 letter words."""
    rng = np.random.default_rng(seed)
    return [
        "".join(
            _LETTERS[int(i)]
            for i in rng.integers(0, len(_LETTERS), int(rng.integers(6, 10)))
        )
        for _ in range(size)
    ]


VOCAB: Final = vocabulary(1)


def page_text(page: int) -> str:
    """One page of prose, two paragraphs, no other page like it."""
    rng = np.random.default_rng(page)
    words: list[str] = []
    while sum(len(w) + 1 for w in words) < PAGE_CHARS:
        words.append(VOCAB[int(rng.integers(0, len(VOCAB)))])
    text = " ".join(words)[:PAGE_CHARS]
    return text[: PAGE_CHARS // 2] + ".\n\n" + text[PAGE_CHARS // 2 + 3 :]


def book(first: int = 5, last: int = 120) -> tuple[str, dict[int, int]]:
    """A synthetic ebook; returns the text and where each page starts in it."""
    parts = [FRONT]
    starts: dict[int, int] = {}
    for page in range(first, last + 1):
        starts[page] = sum(len(p) for p in parts)
        parts.append(page_text(page) + "\n\n")
    parts.append("THE END\n\n↑ A footnote added by the editors of this edition.\n\n")
    parts.append("This e-book comes from a free library. " * 20 + "\n")
    return "".join(parts), starts


def ocr(page: int, *, drop: float = 0.2) -> str:
    """The page as a camera and Tesseract see it: words lost, case mangled."""
    rng = np.random.default_rng(page * 7)
    words = [w for w in page_text(page).split() if rng.random() > drop]
    return " ".join(w.upper() if rng.random() < 0.1 else w for w in words)


TEXT, STARTS = book()


def middle(page: int) -> int:
    """An offset in the middle of ``page`` of :data:`TEXT`."""
    return STARTS[page] + PAGE_CHARS // 2
