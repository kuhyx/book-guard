# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A second look for a page number the whole-page reading missed.

Measured 2026-10-30 on three photos of a chapter opener (p. 9, "WPROWADZENIE
/ DLACZEGO STOICYZM?"): the "9" sits between two swash ornaments at the foot
of the page. Tesseract's page layout (psm 3) either dropped that line or
read it as one word, ``%79—3-—&)9``. Sparse text (psm 11) on the unflattened
page splits it into ``z 9 s”``: the 9 at 86-97, the swashes at 26-55.

So this pass reads the page sparse, lets unsure line-mates go (see
:func:`book_guard._pagenum.lone_numbers`) and keeps a number only when the
tight-crop reader reads its box as that number and no setting reads
anything else.
Unanimity is the guard against a flipped glyph: psm 12 read the same 9 as
6, and a 9 is the one digit whose upside-down twin is a valid page.

It runs only when the whole page offered no candidate, so a page that read
before reads exactly as before -- and only on a page the main reading
holds real words on. Unanimity cannot see a page turned the wrong way as a
whole: both reads then see the same 6-shaped glyph (the p. 9 photos turned
180 read 6 every time).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Final

from book_guard._ocr import tesseract, words
from book_guard._pagenum import lone_numbers, read_box

if TYPE_CHECKING:
    from book_guard._ocr import Scan

UPRIGHT_WORDS: Final = 10
"""Confident words (80+, 3+ letters) the main reading must hold first.

Measured 2026-10-30: 28-62 on upright pages (the p. 9 opener, p. 7), 0-3
on the same pages turned 180, 1 on the p. 151 photo ``upright`` turned
the wrong way.
"""
_SURE_CONF: Final = 80.0
_SURE_LEN: Final = 3


def reads_upright(page: Scan) -> bool:
    """Whether the main reading found enough real words to trust the turn."""
    sure = sum(
        1
        for word in page.words
        if word.conf >= _SURE_CONF
        and len(word.text) >= _SURE_LEN
        and word.text.isalpha()
    )
    return sure >= UPRIGHT_WORDS


def sparse_candidates(page: Scan) -> list[int]:
    """Lone numbers near an edge in a sparse reading, each confirmed by its box."""
    if not reads_upright(page):
        return []
    small = page.image.copy()
    small.thumbnail(page.size)  # the scale the main reading used
    read = words(tesseract(small, "-l", "pol", "--psm", "11", "tsv"))
    scale = page.image.width / small.width
    found: list[int] = []
    for word in lone_numbers(read, small.height, ignore_unsure=True):
        left, top, right, bottom = (round(v * scale) for v in word.box)
        number = int(word.text)
        if read_box(page.image, (left, top, right, bottom)) == [number]:
            found.append(number)
    return list(dict.fromkeys(found))
