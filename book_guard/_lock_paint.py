# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Painters for the lock window's read-only column: icons, bars, numbers.

Colours and font come from the shared gatelock palette (unified design
system), like the sibling lockers; nothing here invents a hex value.
"""

from __future__ import annotations

import tkinter as tk
from typing import TYPE_CHECKING, Final

from gatelock import LockConfig

from book_guard import _icons, _pictos

if TYPE_CHECKING:
    from book_guard._lock_state import Shared

_CONFIG: Final = LockConfig()
BG: Final = _CONFIG.palette.bg
FG: Final = _CONFIG.palette.fg
MUTED: Final = _CONFIG.palette.muted
ACCENT: Final = _CONFIG.palette.accent
DANGER: Final = _CONFIG.palette.danger
SUCCESS: Final = _CONFIG.palette.success
ON_FILL: Final = _CONFIG.palette.on_fill
FIELD_BG: Final = _CONFIG.palette.field_bg
FONT: Final = _CONFIG.typography.font_family
WRAP_PX: Final = 640
"""The shared line-length cap (unified design system rule 21)."""
BAR_W: Final = 360
SPINNER: Final = "◐◓◑◒"
"""Busy cue: a half-disc turning. Plain geometric shapes, never emoji (Tk 8.6)."""


def icon(parent: tk.Misc, name: str, *, size: int = 28, color: str = FG) -> tk.Canvas:
    """A square canvas with icon ``name`` drawn on it."""
    canvas = tk.Canvas(
        parent, width=size, height=size, bg=BG, highlightthickness=0, bd=0
    )
    _icons.draw(canvas, name, size=size, color=color)
    return canvas


def num(parent: tk.Misc, text: str, *, size: int = 16, fg: str = FG) -> tk.Label:
    """A bold numeral label."""
    return tk.Label(parent, text=text, bg=BG, fg=fg, font=(FONT, size, "bold"))


def _gauge(parent: tk.Misc, g: _pictos.Gauge) -> None:
    row = tk.Frame(parent, bg=BG)
    row.pack(anchor="w", pady=4)
    color = SUCCESS if g.done else (DANGER if g.icon == _pictos.DEBT else ACCENT)
    icon(row, g.icon, color=color).pack(side="left", padx=(0, 12))
    draw_bar(row, g.value, g.total, g.mark, color).pack(side="left")
    num(row, f"{g.value}/{g.total}").pack(side="left", padx=12)
    if g.done:
        icon(row, _pictos.OK, size=24, color=SUCCESS).pack(side="left")


def draw_bar(
    parent: tk.Misc, value: int, total: int, mark: int | None, color: str
) -> tk.Canvas:
    """A track, the filled part, and a light tick at the pace line."""
    canvas = tk.Canvas(
        parent, width=BAR_W, height=16, bg=FIELD_BG, highlightthickness=0, bd=0
    )
    if total:
        canvas.create_rectangle(
            0, 0, BAR_W * min(1, value / total), 16, fill=color, width=0
        )
        if mark is not None:
            x = BAR_W * min(1, mark / total)
            canvas.create_line(x, 0, x, 16, fill=FG, width=3)
    return canvas


def _chore(parent: tk.Misc, chore: _pictos.Chore) -> None:
    row = tk.Frame(parent, bg=BG)
    row.pack(anchor="w", pady=4)
    icon(row, chore.icon, size=36, color=ACCENT).pack(side="left", padx=(0, 12))
    num(row, chore.number, size=20, fg=ACCENT).pack(side="left")
    if chore.badge:
        icon(row, chore.badge, size=36, color=ACCENT).pack(side="left", padx=12)


def _entry(parent: tk.Misc, e: _pictos.Entry) -> None:
    row = tk.Frame(parent, bg=BG)
    row.pack(anchor="w", pady=2)
    for text in (e.pages, e.size, e.when):
        tk.Label(row, text=text, bg=BG, fg=MUTED, font=(FONT, 12)).pack(
            side="left", padx=(0, 14)
        )
    ok = e.mark == _pictos.OK
    icon(row, e.mark, size=22, color=SUCCESS if ok else MUTED).pack(side="left")
    if e.number:
        tk.Label(row, text=e.number, bg=BG, fg=MUTED, font=(FONT, 12)).pack(
            side="left", padx=6
        )


def _paint_status(body: tk.Frame, shared: Shared) -> None:
    for child in body.winfo_children():
        child.destroy()
    view = shared.view
    if view is None:
        return
    head = tk.Frame(body, bg=BG)
    head.pack(anchor="w", pady=(0, 20))
    state = _pictos.LOCK if view.locked else _pictos.UNLOCK
    icon(head, state, size=64, color=DANGER if view.locked else SUCCESS).pack(
        side="left", padx=(0, 20)
    )
    icon(head, _pictos.BOOK, size=64, color=ACCENT).pack(side="left")
    book = tk.Frame(body, bg=BG)
    book.pack(anchor="w", pady=(0, 12))
    label = view.book or "?"
    pages = f"  ▤{view.last_page}" if view.last_page else ""
    tk.Label(
        book, text=label + pages, bg=BG, fg=FG, font=(FONT, 14), wraplength=WRAP_PX
    ).pack(anchor="w")
    for g in view.gauges:
        _gauge(body, g)
    for c in view.chores:
        _chore(body, c)
    for e in view.entries:
        _entry(body, e)


def build_status(parent: tk.Misc, shared: Shared) -> tk.Frame:
    """The read-only column every output shows."""
    parent.configure({"bg": BG})
    column = tk.Frame(parent, bg=BG)
    column.place(relx=0.5, rely=0.5, anchor="center")
    body = tk.Frame(column, bg=BG)
    body.pack(anchor="w")
    shared.listen(lambda: _paint_status(body, shared))
    return column
