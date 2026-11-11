# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""One pencilled glyph, put into the shape the digit network was trained on.

The network (:mod:`book_guard._pencil_net`) is MNIST-class: a 28x28 picture,
the digit 20 px on its long side, centred by its centre of mass. A glyph
arrives here as a bool mask cut tight to its box. Everything below is integer
index arithmetic on purpose: ``app/lib/src/pencil_norm.dart`` ports it line for
line, and ``app/test/fixtures/pencil_goldens.json`` keeps the two in step.

Pencil is thin: a photographed stroke is 5-8 % of the digit's height, MNIST's
is 14 %. So the stroke is first widened to ``width_frac`` of the glyph (a
printed or thick stroke is left alone), then the glyph is squeezed to 20 px.
"""

from __future__ import annotations

from typing import Final

import numpy as np
from numpy.typing import NDArray

FIELD: Final = 28
"""Side of the network's picture."""
GLYPH: Final = 20
"""The glyph's long side inside the picture."""
_CENTRE: Final = (FIELD - 1) / 2

Mask = NDArray[np.bool_]
Picture = NDArray[np.float64]


def stroke_width(mask: Mask) -> float:
    """Mean stroke width in pixels: twice the area over the edge pixels.

    Exact for a straight stroke (``w*L`` area, ``2*L`` edge) and good enough
    for a digit; a mask with no edge (nothing, or a filled box) is as wide
    as it is tall.
    """
    padded = np.pad(mask, 1)
    inside = (
        padded[1:-1, 1:-1]
        & padded[:-2, 1:-1]
        & padded[2:, 1:-1]
        & padded[1:-1, :-2]
        & padded[1:-1, 2:]
    )
    edge = int(np.count_nonzero(mask & ~inside))
    if edge == 0:
        return float(max(mask.shape))
    return 2.0 * int(np.count_nonzero(mask)) / edge


def thicken(mask: Mask, radius: int) -> Mask:
    """``mask`` grown by ``radius`` pixels in every direction (square kernel)."""
    if radius <= 0:
        return mask
    grown = np.pad(mask, radius)
    rows = grown.copy()
    for shift in range(1, radius + 1):
        rows[shift:] |= grown[:-shift]
        rows[:-shift] |= grown[shift:]
    out = rows.copy()
    for shift in range(1, radius + 1):
        out[:, shift:] |= rows[:, :-shift]
        out[:, :-shift] |= rows[:, shift:]
    return out


def _ranges(source: int, target: int) -> tuple[NDArray[np.intp], NDArray[np.intp]]:
    """Source index range ``[low, high)`` behind each of ``target`` cells."""
    cell = np.arange(target)
    low = (cell * source) // target
    high = np.maximum(low + 1, -((-(cell + 1) * source) // target))
    return low, high


def squeeze(mask: Mask, height: int, width: int) -> Picture:
    """``mask`` as a ``height`` x ``width`` picture of ink shares.

    Each cell is the share of ink in the block of pixels behind it (every
    block holds at least one pixel).
    """
    rows = _ranges(mask.shape[0], height)
    cols = _ranges(mask.shape[1], width)
    total = np.zeros((mask.shape[0] + 1, mask.shape[1] + 1), dtype=np.int64)
    total[1:, 1:] = mask.astype(np.int64).cumsum(0).cumsum(1)
    ink = (
        total[np.ix_(rows[1], cols[1])]
        - total[np.ix_(rows[0], cols[1])]
        - total[np.ix_(rows[1], cols[0])]
        + total[np.ix_(rows[0], cols[0])]
    )
    area = np.outer(rows[1] - rows[0], cols[1] - cols[0])
    return ink / area


def recentre(picture: Picture) -> Picture:
    """``picture`` moved by whole pixels so its centre of mass is the field's."""
    mass = float(picture.sum())
    if mass <= 0:
        return picture
    ys, xs = np.indices(picture.shape)
    shift_y = int(np.floor(_CENTRE - float((picture * ys).sum()) / mass + 0.5))
    shift_x = int(np.floor(_CENTRE - float((picture * xs).sum()) / mass + 0.5))
    moved = np.zeros_like(picture)
    size = picture.shape[0]
    src_y = slice(max(0, -shift_y), min(size, size - shift_y))
    src_x = slice(max(0, -shift_x), min(size, size - shift_x))
    dst_y = slice(max(0, shift_y), min(size, size + shift_y))
    dst_x = slice(max(0, shift_x), min(size, size + shift_x))
    moved[dst_y, dst_x] = picture[src_y, src_x]
    return moved


def normalise(mask: Mask, width_frac: float) -> Picture:
    """The 28x28 picture of a glyph mask cut tight to its box.

    ``width_frac`` is the stroke width, as a share of the glyph's long side,
    the glyph is widened to when thinner (see :func:`stroke_width`).
    """
    side = max(mask.shape)
    grow = max(0, int(np.floor((width_frac * side - stroke_width(mask)) / 2 + 0.5)))
    grown = thicken(mask, grow)
    scale = GLYPH / max(grown.shape)
    height = max(1, int(np.floor(grown.shape[0] * scale + 0.5)))
    width = max(1, int(np.floor(grown.shape[1] * scale + 0.5)))
    field = np.zeros((FIELD, FIELD), dtype=np.float64)
    top, left = (FIELD - height) // 2, (FIELD - width) // 2
    field[top : top + height, left : left + width] = squeeze(grown, height, width)
    return recentre(field)
