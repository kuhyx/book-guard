# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Strokes of ink in a margin, joined into patches and glyphs.

The geometry under :mod:`book_guard._pencil_find`; its Dart port is
``app/lib/src/pencil_blob.dart``. Pure loops over ints, like the port.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Final

import numpy as np

from book_guard._patch import Patch

if TYPE_CHECKING:
    from numpy.typing import NDArray

_MIN_AREA: Final = 0.03
"""Ink specks smaller than this many unit-squares are dust."""
_MIN_SIDE: Final = 0.2
"""Strokes shorter than this many text lines (and thinner) are dust."""
_MAX_SIDE: Final = 6.0
"""Ink bigger than this many text lines (a dark table edge) is no glyph."""
_JOIN: Final = 1.0
"""Strokes within this many text lines of each other are one patch."""
_OVERLAP: Final = 0.5
"""Strokes sharing this much of the narrower one's columns are one glyph."""
_NEIGHBOURS: Final = tuple(
    (dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx
)


@dataclass(frozen=True)
class Blob:
    """One 8-connected run of ink: its box and its pixels."""

    box: Patch
    ys: NDArray[np.intp]
    xs: NDArray[np.intp]


def _flood(
    ink: NDArray[np.bool_], seen: NDArray[np.bool_], start: tuple[int, int]
) -> list[tuple[int, int]]:
    rows, cols = ink.shape
    seen[start] = True
    stack = [start]
    cells = []
    while stack:
        y, x = stack.pop()
        cells.append((y, x))
        for dy, dx in _NEIGHBOURS:
            ny, nx = y + dy, x + dx
            if 0 <= ny < rows and 0 <= nx < cols and ink[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                stack.append((ny, nx))
    return cells


def blobs(  # pylint: disable=too-many-locals  # one flat flood fill, like its port
    ink: NDArray[np.bool_],
    region: tuple[int, int, int, int],
    unit: float,
    busy: float,
) -> list[Blob]:
    """Glyph-sized runs of ink in ``region`` (top, bottom, left, right).

    A run that touches the region's edge, or that is dust or too big, is
    dropped; so is the whole region when more than ``busy`` of it is ink.
    Coordinates are the whole image's.
    """
    top, bottom, left, right = region
    cut = ink[top:bottom, left:right]
    if cut.mean() > busy:
        return []
    seen = np.zeros_like(cut)
    found = []
    for y, x in zip(*np.nonzero(cut), strict=True):
        if seen[y, x]:
            continue
        cells = _flood(cut, seen, (int(y), int(x)))
        ys = np.array([c[0] for c in cells], dtype=np.intp)
        xs = np.array([c[1] for c in cells], dtype=np.intp)
        box = Patch(int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
        if (
            len(cells) >= _MIN_AREA * unit * unit
            and _MIN_SIDE * unit <= max(box.height, box.width) <= _MAX_SIDE * unit
            and not box.touches((cut.shape[1], cut.shape[0]))
        ):
            global_box = Patch(
                box.left + left, box.top + top, box.right + left, box.bottom + top
            )
            found.append(Blob(global_box, ys + top, xs + left))
    return found


def patches(found: list[Blob], unit: float) -> list[tuple[Patch, list[Blob]]]:
    """Blobs within a text line of each other, joined (transitively)."""
    root = list(range(len(found)))

    def find(i: int) -> int:
        while root[i] != i:
            root[i] = root[root[i]]
            i = root[i]
        return i

    for i, first in enumerate(found):
        for j in range(i + 1, len(found)):
            if first.box.joins(found[j].box, _JOIN * unit):
                root[find(j)] = find(i)
    groups: dict[int, list[Blob]] = {}
    for i, blob in enumerate(found):
        groups.setdefault(find(i), []).append(blob)
    result = []
    for members in groups.values():
        box = members[0].box
        for member in members[1:]:
            box = box.merged(member.box)
        result.append((box, members))
    return result


def merge_glyphs(strokes: list[Blob]) -> list[Patch]:
    """Boxes of the glyphs in a patch, left to right.

    Strokes whose columns overlap are one glyph (the bar and the stem of
    a 4, the dot-less parts of a broken 5).
    """
    glyphs: list[Patch] = []
    for stroke in sorted(strokes, key=lambda s: s.box.left):
        box = stroke.box
        for index, glyph in enumerate(glyphs):
            overlap = min(glyph.right, box.right) - max(glyph.left, box.left) + 1
            if overlap >= _OVERLAP * min(glyph.width, box.width):
                glyphs[index] = glyph.merged(box)
                break
        else:
            glyphs.append(box)
    return sorted(glyphs, key=lambda g: g.left)
