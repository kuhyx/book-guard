# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Pictograms for the lock window, drawn on a Tk canvas.

Why drawn and not font glyphs: Tk 8.6 on X11 can crash on colour-emoji
glyphs, and a canvas drawing looks the same on every box. Each icon is data
on a 24x24 grid, so scaling is one multiply and a test can check that every
icon the view model names has a drawing.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Final

if TYPE_CHECKING:
    import tkinter as tk

Prim = tuple[str, tuple[int, ...], bool]
"""(kind, grid coordinates, filled): kind is rect, oval, line or poly."""

GRID: Final = 24

SHAPES: Final[dict[str, tuple[Prim, ...]]] = {
    "book": (
        ("poly", (2, 5, 12, 7, 12, 20, 2, 18), False),
        ("poly", (22, 5, 12, 7, 12, 20, 22, 18), False),
    ),
    "camera": (
        ("rect", (2, 7, 22, 20), False),
        ("rect", (8, 4, 16, 7), True),
        ("oval", (8, 9, 16, 17), False),
    ),
    "pencil": (
        ("poly", (4, 20, 5, 15, 16, 4, 20, 8, 9, 19), False),
        ("line", (14, 6, 18, 10), False),
    ),
    "lock": (
        ("rect", (5, 11, 19, 22), True),
        ("line", (8, 11, 8, 6, 12, 2, 16, 6, 16, 11), False),
    ),
    "unlock": (
        ("rect", (5, 11, 19, 22), True),
        ("line", (8, 11, 8, 6, 12, 2, 16, 6, 16, 8), False),
    ),
    "ok": (("line", (4, 13, 10, 19, 21, 6), False),),
    "no": (("line", (5, 5, 19, 19), False), ("line", (19, 5, 5, 19), False)),
    "fast": (
        ("line", (3, 5, 11, 12, 3, 19), False),
        ("line", (12, 5, 20, 12, 12, 19), False),
    ),
    "overlap": (("rect", (3, 3, 15, 15), False), ("rect", (9, 9, 21, 21), False)),
    "sick": (
        (
            "poly",
            (
                9,
                3,
                15,
                3,
                15,
                9,
                21,
                9,
                21,
                15,
                15,
                15,
                15,
                21,
                9,
                21,
                9,
                15,
                3,
                15,
                3,
                9,
                9,
                9,
            ),
            True,
        ),
    ),
    "retry": (
        (
            "line",
            (19, 12, 18, 7, 14, 4, 9, 5, 5, 9, 5, 14, 9, 19, 14, 20, 18, 17),
            False,
        ),
        ("poly", (19, 3, 19, 10, 12, 10), True),
    ),
    "warn": (
        ("poly", (12, 3, 22, 21, 2, 21), False),
        ("line", (12, 9, 12, 15), False),
        ("oval", (11, 17, 13, 19), True),
    ),
    "month": (
        ("rect", (3, 5, 21, 21), False),
        ("line", (3, 10, 21, 10), False),
        ("line", (8, 3, 8, 7), False),
        ("line", (16, 3, 16, 7), False),
    ),
    "day": (
        ("oval", (8, 8, 16, 16), True),
        ("line", (12, 2, 12, 5), False),
        ("line", (12, 19, 12, 22), False),
        ("line", (2, 12, 5, 12), False),
        ("line", (19, 12, 22, 12), False),
    ),
    "debt": (("poly", (3, 6, 21, 6, 12, 20), True),),
    "escape": (
        ("rect", (3, 3, 13, 21), False),
        ("line", (9, 12, 22, 12), False),
        ("line", (18, 8, 22, 12, 18, 16), False),
    ),
}


def draw(canvas: tk.Canvas, name: str, *, size: int, color: str) -> None:
    """Paint icon ``name`` filling a ``size``-pixel square canvas."""
    k = size / GRID
    width = max(2, round(size / 10))
    for kind, coords, filled in SHAPES[name]:
        pts = [c * k for c in coords]
        fill = color if filled else ""
        if kind == "rect":
            canvas.create_rectangle(*pts, outline=color, fill=fill, width=width)
        elif kind == "oval":
            canvas.create_oval(*pts, outline=color, fill=fill, width=width)
        elif kind == "poly":
            canvas.create_polygon(*pts, outline=color, fill=fill, width=width)
        else:
            canvas.create_line(*pts, fill=color, width=width, capstyle="round")
