# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Patches of ink: boxes around strokes, joined by closeness.

The geometry under :mod:`book_guard._margin`, on a mask of ink pixels.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from PIL import Image


@dataclass(frozen=True)
class Patch:
    """A box of ink in a margin's own pixels (after the shrink)."""

    left: int
    top: int
    right: int
    bottom: int

    @property
    def height(self) -> int:
        """Rows covered."""
        return self.bottom - self.top + 1

    @property
    def width(self) -> int:
        """Columns covered."""
        return self.right - self.left + 1

    def joins(self, other: Patch, gap: float) -> bool:
        """Whether the two boxes lie within ``gap`` of each other."""
        return (
            self.left - gap <= other.right
            and other.left - gap <= self.right
            and self.top - gap <= other.bottom
            and other.top - gap <= self.bottom
        )

    def merged(self, other: Patch) -> Patch:
        """The smallest box holding both."""
        return Patch(
            min(self.left, other.left),
            min(self.top, other.top),
            max(self.right, other.right),
            max(self.bottom, other.bottom),
        )

    def touches(self, size: tuple[int, int]) -> bool:
        """Whether the box reaches the edge of an image of ``size``."""
        return (
            self.left == 0
            or self.top == 0
            or self.right == size[0] - 1
            or self.bottom == size[1] - 1
        )

    def shares_line(self, other: Patch) -> bool:
        """Whether the vertical extents overlap by half the shorter box."""
        overlap = min(self.bottom, other.bottom) - max(self.top, other.top) + 1
        return overlap * 2 >= min(self.height, other.height)


def find_strokes(mask: Image.Image) -> list[Patch]:
    """Every 4-connected run of ink in ``mask``, as its bounding box."""
    width, height = mask.size
    pixels = list(mask.get_flattened_data())
    seen: set[tuple[int, int]] = set()
    found: list[Patch] = []
    for y in range(height):
        for x in range(width):
            if not pixels[y * width + x] or (x, y) in seen:
                continue
            seen.add((x, y))
            stack = [(x, y)]
            box = Patch(x, y, x, y)
            while stack:
                cx, cy = stack.pop()
                box = box.merged(Patch(cx, cy, cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if (
                        0 <= nx < width
                        and 0 <= ny < height
                        and pixels[ny * width + nx]
                        and (nx, ny) not in seen
                    ):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            found.append(box)
    return found


def join_strokes(strokes: list[Patch], gap: float) -> list[Patch]:
    """Strokes within ``gap`` of each other, joined (transitively) into patches."""
    root = list(range(len(strokes)))

    def find(i: int) -> int:
        while root[i] != i:
            root[i] = root[root[i]]
            i = root[i]
        return i

    for i, first in enumerate(strokes):
        for j in range(i + 1, len(strokes)):
            if first.joins(strokes[j], gap):
                root[find(j)] = find(i)
    joined: dict[int, Patch] = {}
    for i, stroke in enumerate(strokes):
        top = find(i)
        joined[top] = joined[top].merged(stroke) if top in joined else stroke
    return list(joined.values())
