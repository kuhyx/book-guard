# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The lock window's widgets. Rendering only -- no decisions, no I/O.

Colours and font come from the shared gatelock palette (unified design
system), like the sibling lockers; nothing here invents a hex value.
"""

from __future__ import annotations

from dataclasses import dataclass
import tkinter as tk
from typing import TYPE_CHECKING, Final

from gatelock import LockConfig

if TYPE_CHECKING:
    from collections.abc import Callable

_CONFIG: Final = LockConfig()
BG: Final = _CONFIG.palette.bg
FG: Final = _CONFIG.palette.fg
MUTED: Final = _CONFIG.palette.muted
ACCENT: Final = _CONFIG.palette.accent
DANGER: Final = _CONFIG.palette.danger
FIELD_BG: Final = _CONFIG.palette.field_bg
FONT: Final = _CONFIG.typography.font_family
WRAP_PX: Final = 640
"""The shared line-length cap (unified design system rule 21)."""


@dataclass
class SharedVars:
    """Tk variables mastered on the root, so every monitor shows one state."""

    status: tk.StringVar
    todo: tk.StringVar
    quiz_title: tk.StringVar
    feedback: tk.StringVar


@dataclass
class PrimaryWidgets:
    """The input widgets, built on the primary output only."""

    summary: tk.Text
    submit: tk.Button
    escape: tk.Entry


def make_vars(root: tk.Misc) -> SharedVars:
    """Create the shared variables once."""
    return SharedVars(
        status=tk.StringVar(master=root),
        todo=tk.StringVar(master=root),
        quiz_title=tk.StringVar(master=root),
        feedback=tk.StringVar(master=root),
    )


def _label(parent: tk.Misc, var: tk.StringVar, *, size: int, fg: str = FG) -> tk.Label:
    label = tk.Label(
        parent,
        textvariable=var,
        bg=BG,
        fg=fg,
        font=(FONT, size),
        wraplength=WRAP_PX,
        justify="left",
    )
    label.pack(anchor="w", pady=(0, 16))
    return label


def build_status(parent: tk.Misc, shared: SharedVars) -> tk.Frame:
    """The read-only column every output shows."""
    parent.configure({"bg": BG})
    column = tk.Frame(parent, bg=BG)
    column.place(relx=0.5, rely=0.5, anchor="center")
    title = tk.Label(
        column, text="Read your book", bg=BG, fg=ACCENT, font=(FONT, 32, "bold")
    )
    title.pack(anchor="w", pady=(0, 24))
    _label(column, shared.status, size=14)
    _label(column, shared.todo, size=14, fg=ACCENT)
    return column


def build_inputs(
    column: tk.Frame,
    shared: SharedVars,
    *,
    on_submit: Callable[[], None],
    on_escape: Callable[[], None],
) -> PrimaryWidgets:
    """Summary box, submit button and escape field (primary output only)."""
    _label(column, shared.quiz_title, size=12, fg=MUTED)
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
    summary.bind("<Control-Return>", lambda _event: on_submit())
    submit = tk.Button(
        column,
        text="Submit summary (Ctrl+Enter)",
        command=on_submit,
        bg=ACCENT,
        fg=BG,
        relief="flat",
    )
    submit.pack(anchor="w", pady=(0, 8))
    _label(column, shared.feedback, size=12, fg=DANGER)
    hint = tk.Label(
        column,
        text="Escape hatch (limited per month) -- type the sentence and press Enter:",
        bg=BG,
        fg=MUTED,
        font=(FONT, 10),
    )
    hint.pack(anchor="w", pady=(24, 4))
    escape = tk.Entry(
        column, width=64, bg=FIELD_BG, fg=FG, insertbackground=FG, relief="flat"
    )
    escape.pack(anchor="w")
    escape.bind("<Return>", lambda _event: on_escape())
    return PrimaryWidgets(summary=summary, submit=submit, escape=escape)


def install_demo_close(parent: tk.Misc, on_close: Callable[[], None]) -> None:
    """A close button so a demo can never trap the developer."""
    tk.Button(parent, text="Close demo", command=on_close).place(
        relx=0.98, rely=0.02, anchor="ne"
    )
