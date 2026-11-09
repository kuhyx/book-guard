# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The lock window's input widgets. Rendering only -- no decisions, no I/O.

No sentences: icons drawn by ``_icons``, bars, numbers, colour. The only
words on screen are user content (the book's title, the topics the grader
says a summary lacks) and the escape sentence the reader must type.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import tkinter as tk
from typing import TYPE_CHECKING

from book_guard import _pictos
from book_guard._lock_paint import (
    ACCENT,
    BG,
    DANGER,
    FG,
    FIELD_BG,
    FONT,
    MUTED,
    ON_FILL,
    SPINNER,
    SUCCESS,
    WRAP_PX,
    build_status,
    draw_bar,
    icon,
    num,
)
from book_guard._lock_state import Shared
from book_guard._quiz import MIN_SUMMARY_CHARS

if TYPE_CHECKING:
    from collections.abc import Callable

__all__ = [
    "PrimaryWidgets",
    "build_inputs",
    "build_status",
    "install_demo_close",
    "make_vars",
]


@dataclass
class PrimaryWidgets:
    """The input widgets, built on the primary output only."""

    summary: tk.Text
    submit: tk.Button
    escape: tk.Entry
    meter: Callable[[], None] = field(default=lambda: None)
    """Repaint the length bar after the text changed without a key press."""


def make_vars(_root: tk.Misc) -> Shared:
    """The shared state (kept under its old name for the lock's wiring)."""
    return Shared()


def _paint_feedback(row: tk.Frame, shared: Shared) -> None:
    for child in row.winfo_children():
        child.destroy()
    fb = shared.feedback
    if fb.busy:
        num(row, SPINNER[shared.phase % len(SPINNER)], size=24, fg=ACCENT).pack(
            side="left"
        )
        return
    color = SUCCESS if fb.icon == _pictos.OK else DANGER
    if fb.icon:
        icon(row, fb.icon, size=32, color=color).pack(side="left", padx=(0, 12))
    if fb.detail:
        tk.Label(
            row,
            text=fb.detail,
            bg=BG,
            fg=MUTED,
            font=(FONT, 12),
            wraplength=WRAP_PX,
            justify="left",
        ).pack(side="left")


def _escape_row(column: tk.Frame, shared: Shared) -> tk.Entry:
    row = tk.Frame(column, bg=BG)
    row.pack(anchor="w", pady=(28, 0))
    holder = tk.Frame(row, bg=BG)
    holder.pack(side="left", padx=(0, 12))

    def paint() -> None:
        for child in holder.winfo_children():
            child.destroy()
        view = shared.view
        if view is None:
            return
        icon(holder, _pictos.ESCAPE, size=28, color=DANGER).pack(side="left")
        dots = tk.Canvas(
            holder,
            width=26 * view.escapes_total,
            height=28,
            bg=BG,
            highlightthickness=0,
        )
        for i in range(view.escapes_total):
            fill = DANGER if i < view.escapes_left else ""
            dots.create_oval(
                4 + 26 * i, 6, 22 + 26 * i, 24, outline=DANGER, fill=fill, width=2
            )
        dots.pack(side="left", padx=8)

    shared.listen(paint)
    return tk.Entry(
        row,
        width=48,
        bg=FIELD_BG,
        fg=FG,
        insertbackground=FG,
        relief="flat",
        highlightthickness=2,
        highlightbackground=DANGER,
        highlightcolor=DANGER,
    )


def build_inputs(
    column: tk.Frame,
    shared: Shared,
    *,
    on_submit: Callable[[], None],
    on_escape: Callable[[], None],
) -> PrimaryWidgets:
    """Summary box, submit button and escape field (primary output only)."""
    wait = tk.Frame(column, bg=BG)
    wait.pack(anchor="w", pady=(16, 4))

    def paint_wait() -> None:
        for child in wait.winfo_children():
            child.destroy()
        view = shared.view
        pencil = [c for c in view.chores if c.icon == _pictos.PENCIL] if view else []
        if pencil:
            icon(wait, _pictos.PENCIL, size=28, color=MUTED).pack(side="left")
            tk.Label(
                wait, text=pencil[0].number, bg=BG, fg=MUTED, font=(FONT, 12)
            ).pack(side="left", padx=8)

    shared.listen(paint_wait)
    summary = tk.Text(
        column,
        width=64,
        height=6,
        wrap="word",
        bg=FIELD_BG,
        fg=FG,
        insertbackground=FG,
        font=(FONT, 12),
        relief="flat",
    )
    summary.pack(anchor="w", pady=(0, 8))
    gauge = tk.Frame(column, bg=BG)
    gauge.pack(anchor="w", pady=(0, 8))

    def meter() -> None:
        for child in gauge.winfo_children():
            child.destroy()
        size = len(summary.get("1.0", "end").strip())
        full = size >= MIN_SUMMARY_CHARS
        draw_bar(
            gauge, size, MIN_SUMMARY_CHARS, None, SUCCESS if full else ACCENT
        ).pack(side="left")
        if full:
            icon(gauge, _pictos.OK, size=22, color=SUCCESS).pack(side="left", padx=8)

    meter()
    summary.bind("<KeyRelease>", lambda _event: meter())
    summary.bind("<Control-Return>", lambda _event: on_submit())
    submit = tk.Button(
        column,
        text="✓",
        command=on_submit,
        bg=ACCENT,
        fg=ON_FILL,
        activebackground=SUCCESS,
        font=(FONT, 18, "bold"),
        width=6,
        relief="flat",
    )
    submit.pack(anchor="w", pady=(0, 8))
    feedback = tk.Frame(column, bg=BG)
    feedback.pack(anchor="w", pady=(8, 0))
    shared.listen(lambda: _paint_feedback(feedback, shared))
    escape = _escape_row(column, shared)
    escape.pack(side="left")
    escape.bind("<Return>", lambda _event: on_escape())
    return PrimaryWidgets(summary=summary, submit=submit, escape=escape, meter=meter)


def install_demo_close(parent: tk.Misc, on_close: Callable[[], None]) -> None:
    """A close button so a demo can never trap the developer."""
    tk.Button(parent, text="✕", command=on_close, font=(FONT, 14)).place(
        relx=0.98, rely=0.02, anchor="ne"
    )
