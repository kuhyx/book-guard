# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Find a pencilled page number in the margin and read it with the digit net.

Tesseract cannot read handwriting (a clean crop of a pencilled "612" came
back "671"), so this pass skips OCR for the number itself. Given the upright
page as gray pixels and where its text sits, it takes the ink (a pixel darker
than the paper around it) above and below the body, joins strokes into
patches, and keeps a patch only if it looks like pencil in empty paper:
digit-sized, alone on its line, on paper, in the body's column, and grey
rather than black. Each glyph of a kept patch is read by the network
(:mod:`book_guard._pencil_net`) after :mod:`book_guard._pencil_norm`; the
number stands only if every glyph is read the same way at three stroke
widths and with confidence. Anything doubtful is ``None``: a wrong pre-fill
is worse than an empty keypad. Index arithmetic is plain loops over ints on
purpose; ``app/lib/src/pencil_find.dart`` is a line-for-line port, kept in
step by ``app/test/fixtures/pencil_goldens.json``.
"""

from __future__ import annotations

import math
from typing import TYPE_CHECKING, Final

import numpy as np
from numpy.typing import NDArray

from book_guard._pencil_blob import Blob, blobs, merge_glyphs, patches
from book_guard._pencil_norm import normalise

if TYPE_CHECKING:
    from book_guard._patch import Patch
    from book_guard._pencil_net import Net

Body = tuple[int, int, int, int]
Gray = NDArray[np.uint8]

_UNIT_PX: Final = 16
"""A text line is shrunk to about this many pixels: strokes stay 2-4 wide."""
_BLUR: Final = 2.0
"""Paper level is the mean over a window this many lines around a pixel."""
INK_STEP: Final = 12
"""How much darker than the paper (0-255) a pixel is to count as ink."""
_BUSY: Final = 0.35
"""A margin with more ink than this is a dark table or a pattern, not paper."""
_PRINT: Final = 75
"""Ink this much darker than the paper is print or a pen, not pencil."""
_PRINT_SHARE: Final = 0.02
"""...if more than this share of a patch's ink is that dark."""
_HEIGHT: Final = (0.5, 6.0)
_MAX_WIDTH: Final = 3.5
_MAX_PATCHES: Final = 4
_MATE_REACH: Final = 4.0
_PAPER_SHARE: Final = 0.8
FRACS: Final = (0.11, 0.14, 0.18)
"""Stroke widths (share of the glyph's size) each glyph is read at."""
_SURE: Final = 0.7
_MIN_PEAK: Final = 30
"""Pencil shows at least this much darker than the paper; fainter is a shadow."""
_NOT_A_DIGIT: Final = 10
"""The network's eleventh class: a swash, a smudge, half a digit."""
_MAX_DIGITS: Final = 4


def _nearest(value: float) -> int:
    """``value`` rounded half up (the port rounds the same way)."""
    return math.floor(value + 0.5)


def shrink(gray: Gray, factor: int) -> NDArray[np.int64]:
    """``gray`` as the floor of the mean of each factor x factor block."""
    rows, cols = gray.shape[0] // factor, gray.shape[1] // factor
    cut = gray[: rows * factor, : cols * factor].astype(np.int64)
    sums = cut.reshape(rows, factor, cols, factor).sum(axis=(1, 3))
    return sums // (factor * factor)


def paper_map(small: NDArray[np.int64], radius: int) -> NDArray[np.float64]:
    """The mean of ``small`` over the window of ``radius`` around each pixel."""
    total = np.zeros((small.shape[0] + 1, small.shape[1] + 1), dtype=np.int64)
    total[1:, 1:] = small.cumsum(0).cumsum(1)
    rows, cols = np.arange(small.shape[0]), np.arange(small.shape[1])
    top, bottom = (
        np.maximum(rows - radius, 0),
        np.minimum(rows + radius + 1, small.shape[0]),
    )
    left, right = (
        np.maximum(cols - radius, 0),
        np.minimum(cols + radius + 1, small.shape[1]),
    )
    ink = (
        total[np.ix_(bottom, right)]
        - total[np.ix_(top, right)]
        - total[np.ix_(bottom, left)]
        + total[np.ix_(top, left)]
    )
    mean: NDArray[np.float64] = ink / np.outer(bottom - top, right - left)
    return mean


def _median(values: NDArray[np.int64]) -> int:
    """The median of an integer array (the lower middle value)."""
    return int(np.sort(values.reshape(-1))[(values.size - 1) // 2])


def glyph_mask(diff: NDArray[np.float64], blob: Patch) -> NDArray[np.bool_]:
    """The glyph's ink, cut tight: darker than 0.4 of its own peak contrast."""
    box = diff[
        max(0, blob.top - 2) : blob.bottom + 3, max(0, blob.left - 2) : blob.right + 3
    ]
    inked = np.sort(box[box > INK_STEP])
    peak = float(inked[int(0.95 * (inked.size - 1))])
    mask = box > max(INK_STEP, 0.4 * peak)
    ys, xs = np.nonzero(mask)
    return mask[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]


def _digit(net: Net, mask: NDArray[np.bool_]) -> int | None:
    """The digit the glyph is, if all stroke widths agree and are sure."""
    seen = [net.probabilities(normalise(mask, frac)) for frac in FRACS]
    top = {int(p.argmax()) for p in seen}
    if (
        len(top) != 1
        or top == {_NOT_A_DIGIT}
        or min(float(p.max()) for p in seen) < _SURE
    ):
        return None
    return top.pop()


def _read(net: Net, diff: NDArray[np.float64], glyphs: list[Patch]) -> int | None:
    if not 1 <= len(glyphs) <= _MAX_DIGITS:
        return None
    digits = [_digit(net, glyph_mask(diff, glyph)) for glyph in glyphs]
    if None in digits or digits[0] == 0:
        return None
    return int("".join(str(d) for d in digits))


def lone_patches(found: list[Blob], unit: float) -> list[tuple[Patch, list[Blob]]]:
    """Digit-sized patches alone on their line, each with its strokes."""
    low, high = _HEIGHT
    grouped = patches(found, unit)
    boxes = [box for box, _ in grouped]
    lone = []
    for box, strokes in grouped:
        mates = [
            o
            for o in boxes
            if o is not box and box.shares_line(o) and box.joins(o, _MATE_REACH * unit)
        ]
        sized = (
            low * unit <= box.height <= high * unit
            and box.width <= _MAX_WIDTH * box.height
        )
        if sized and not mates:
            lone.append((box, strokes))
    return lone if len(lone) <= _MAX_PATCHES else []


def _pencil(diff: NDArray[np.float64], strokes: list[Blob]) -> bool:
    """Whether the patch's ink is pencil: seen, but little of it print-dark."""
    values = np.concatenate([diff[s.ys, s.xs] for s in strokes])
    return values.max() >= _MIN_PEAK and float((values > _PRINT).mean()) <= _PRINT_SHARE


def find_number(  # pylint: disable=too-many-locals  # one pass, like its port
    net: Net, gray: Gray, body: Body, line: float
) -> int | None:
    """The pencilled page number in the page's margin, or ``None``.

    ``gray`` is the upright page, ``body`` (left, top, right, bottom) the
    text's box in its pixels and ``line`` the text-line height in pixels.
    """
    factor = max(1, math.floor(line / _UNIT_PX))
    unit = line / factor
    small = shrink(gray, factor)
    diff = paper_map(small, _nearest(_BLUR * unit)) - small
    height, width = small.shape
    left, right = (min(v // factor, width) for v in (body[0], body[2]))
    top, bottom = (min(v // factor, height) for v in (body[1], body[3]))
    if bottom <= top or right <= left:
        return None  # the text box lies outside the page: nothing to go by
    paper = _median(small[top:bottom, left:right])
    pad = _nearest(unit)
    columns = (max(0, left - pad), min(small.shape[1], right + pad))
    numbers: set[int] = set()
    for rows in ((0, top), (bottom, small.shape[0])):
        region = (rows[0], rows[1], *columns)
        if rows[1] - rows[0] < unit:
            continue
        found = blobs(diff > INK_STEP, region, unit, _BUSY)
        for box, strokes in lone_patches(found, unit):
            around = small[
                max(0, box.top - pad) : box.bottom + pad + 1,
                max(0, box.left - pad) : box.right + pad + 1,
            ]
            if _median(around) < _PAPER_SHARE * paper or not _pencil(diff, strokes):
                continue
            number = _read(net, diff, merge_glyphs(strokes))
            if number is not None:
                numbers.add(number)
    return numbers.pop() if len(numbers) == 1 else None
