# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A third look: a number alone in the margin, found by its ink, not its glyphs.

Measured 2026-11-09 on three real photos the whole-page reading (psm 3) and
the sparse one (:mod:`book_guard._sparse`) both missed, though
:func:`book_guard._pagenum.read_box` reads each from a hand-placed box
unanimously, so the gap was *finding* the number:

* p. 612, the last page of a novel, no printed number: "612" pencilled by
  the reader below the text. Handwriting is no text to Tesseract at any
  setting, but it is a compact patch of ink in empty paper.
* p. 502, a tiny printed number in the bottom-left corner, far from the text.
* p. 59 (check photo), the "58" of the open spread at the foot of the left
  page.

So this pass does not ask Tesseract where the number is. Above and below the
body text (the words :func:`~book_guard._sparse.reads_upright` already
trusts) it takes the ink -- the page minus its own blurred background, as in
:func:`book_guard._ocr.flatten` -- joins nearby strokes into patches, keeps
the patches the size of a 1-4 digit number that have no mate on their line,
and lets the tight-crop reader read each. A number counts only when every
setting that reads the crop agrees (the :mod:`~book_guard._sparse` guard
against a flipped glyph); a patch that reads as nothing is just a smudge.

Edge tiles read blindly at full resolution gave confident false numbers (a
"1" at conf 97, a "4" from the neighbouring page); there nothing but the
reader stood between a stray glyph and a credited page, here a patch must
also be digit-sized, alone and clear of the text. It runs only when the
whole page and the sparse pass offered no candidate, like the sparse pass.
"""

from __future__ import annotations

from itertools import accumulate
import statistics
from typing import TYPE_CHECKING, Final

from PIL import ImageChops, ImageFilter

from book_guard._pagenum import Box, read_box
from book_guard._patch import Patch, find_strokes, join_strokes
from book_guard._sparse import reads_upright

if TYPE_CHECKING:
    from PIL import Image

    from book_guard._ocr import Scan, Word

_REDUCE: Final = 4
"""Ink is found on the page shrunk by this much: a stroke stays a few pixels
wide, and the pure-Python patch search touches 16x fewer of them."""
_BACKGROUND_BLUR: Final = 30
_INK_STEP: Final = 20
"""How much darker than its surroundings (0-255) a pixel is to count as ink.
Pencil is the faintest thing read: 612 clears it with room to spare."""
_SURE_CONF: Final = 80.0
_SURE_LEN: Final = 3
_JOIN: Final = 1.0
"""Strokes closer than this many text-line heights are one patch."""
_MIN_STROKE: Final = 0.2
"""Ink specks shorter than this many text-line heights are dust."""
_MAX_STROKE: Final = 4.0
"""Ink bigger than this (a dark table edge, the book's shadow) is no glyph."""
_DIGIT_HEIGHT: Final = (0.5, 4.0)
"""Patch height, in text-line heights: 52-232 px against 67 on the photos."""
_MAX_WIDTH: Final = 3.5
"""Four digits are 2.5 heights wide at most; wider is a word."""
_MIN_WIDTH: Final = 0.2
_MATE_REACH: Final = 4.0
"""A patch this many text-line heights away on its own line is a line-mate."""
_PAPER_SHARE: Final = 0.8
"""A patch counts only on paper: around it the page is at least this share as
bright as the paper under the text. Measured on the p. 612 photo: the carpet
below the page gave patches that read "1" and "2 or 3" unanimously."""
_PAPER_REDUCE: Final = 8
_MAX_PATCHES: Final = 4
"""Per margin: more is a busy margin, not a lone number."""


def _ink(margin: Image.Image) -> Image.Image:
    """The margin shrunk, as a mask of what is darker than the paper around it."""
    small = margin.reduce(_REDUCE)
    background = small.filter(ImageFilter.GaussianBlur(_BACKGROUND_BLUR // _REDUCE + 1))
    return ImageChops.subtract(background, small).point(
        lambda v: 255 if v > _INK_STEP else 0
    )


def _median(gray: Image.Image) -> int:
    """The median gray level of ``gray``."""
    levels = gray.histogram()
    half = sum(levels) / 2
    return next(level for level, seen in enumerate(accumulate(levels)) if seen >= half)


def _on_paper(margin: Image.Image, patch: Patch, line: float, paper: int) -> bool:
    """Whether the paper shows around ``patch`` as bright as under the text."""
    pad = round(line)
    around = margin.crop(
        (
            max(0, patch.left * _REDUCE - pad),
            max(0, patch.top * _REDUCE - pad),
            (patch.right + 1) * _REDUCE + pad,
            (patch.bottom + 1) * _REDUCE + pad,
        )
    )
    return _median(around) >= _PAPER_SHARE * paper


def _lone_patches(margin: Image.Image, line: float, paper: int) -> list[Patch]:
    """Digit-sized patches of ink alone on their line, in the margin's shrunk pixels.

    ``line`` is the text-line height in the full image's pixels: every size
    here is a multiple of it, so the same rules hold for a close-up and a
    far shot. ``paper`` is the gray level of the page under the text.
    """
    mask = _ink(margin)
    unit = line / _REDUCE
    strokes = [
        stroke
        for stroke in find_strokes(mask)
        if _MIN_STROKE * unit <= stroke.height <= _MAX_STROKE * unit
        and stroke.width <= _MAX_STROKE * unit
    ]
    patches = join_strokes(strokes, _JOIN * unit)
    low, high = _DIGIT_HEIGHT
    lone: list[Patch] = []
    for patch in patches:
        if patch.touches(mask.size) or not (
            low * unit <= patch.height <= high * unit
            and _MIN_WIDTH * patch.height <= patch.width <= _MAX_WIDTH * patch.height
        ):
            continue
        mates = [
            other
            for other in patches
            if other is not patch
            and patch.shares_line(other)
            and patch.joins(other, _MATE_REACH * unit)
        ]
        if not mates and _on_paper(margin, patch, line, paper):
            lone.append(patch)
    return lone if len(lone) <= _MAX_PATCHES else []


def sure_words(found: tuple[Word, ...]) -> list[Word]:
    """The words read with confidence: 3+ letters, conf 80+."""
    return [
        w
        for w in found
        if w.conf >= _SURE_CONF and len(w.text) >= _SURE_LEN and w.text.isalpha()
    ]


def body_of(page: Scan) -> tuple[Box, float]:
    """The confidently read text's box (full image pixels) and its line height."""
    scale = page.image.width / page.size[0]
    sure = sure_words(page.words)
    box = (
        round(min(w.box[0] for w in sure) * scale),
        round(min(w.box[1] for w in sure) * scale),
        round(max(w.box[2] for w in sure) * scale),
        round(max(w.box[3] for w in sure) * scale),
    )
    return box, scale * statistics.median(w.box[3] - w.box[1] for w in sure)


def margin_candidates(page: Scan) -> list[int]:
    """Numbers alone in the margin above or below the text, each read unanimously."""
    if not reads_upright(page):
        return []
    body, line = body_of(page)
    paper = _median(page.image.crop(body).reduce(_PAPER_REDUCE))
    width, height = page.image.size
    found: list[int] = []
    for top, bottom in ((0, body[1]), (body[3], height)):
        if bottom - top < line:
            continue
        margin = page.image.crop((0, top, width, bottom))
        for patch in _lone_patches(margin, line, paper):
            box: Box = (
                patch.left * _REDUCE,
                top + patch.top * _REDUCE,
                (patch.right + 1) * _REDUCE,
                top + (patch.bottom + 1) * _REDUCE,
            )
            read = read_box(page.image, box)
            if len(read) == 1:
                found.append(read[0])
    return list(dict.fromkeys(found))
