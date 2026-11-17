# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The "end evening" control: one icon in the corner, no words."""

from __future__ import annotations

from typing import TYPE_CHECKING

from book_guard import _pictos
from book_guard._lock_paint import DANGER, icon

if TYPE_CHECKING:
    from collections.abc import Callable
    import tkinter as tk


def add_end_control(parent: tk.Misc, on_end: Callable[[], None]) -> None:
    """Put the end-evening icon on ``parent``, clickable from the first frame."""
    button = icon(parent, _pictos.END, size=48, color=DANGER)
    button.place(relx=0.98, rely=0.02, anchor="ne")
    button.configure(cursor="hand2")
    button.bind("<Button-1>", lambda _event: on_end())
