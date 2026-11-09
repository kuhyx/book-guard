# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""State the lock window's surfaces share: the view model and the feedback."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard import _pictos


@dataclass
class Feedback:
    """What the last action did: an icon name, content text, a busy flag."""

    icon: str = ""
    detail: str = ""
    busy: bool = False


@dataclass
class Shared:
    """State every monitor shows; each surface listens and redraws itself."""

    view: _pictos.View | None = None
    feedback: Feedback = field(default_factory=Feedback)
    phase: int = 0
    _listeners: list[Callable[[], None]] = field(default_factory=list)

    def listen(self, redraw: Callable[[], None]) -> None:
        """Register a surface and paint it once."""
        self._listeners.append(redraw)
        redraw()

    def changed(self) -> None:
        """Repaint every surface."""
        for redraw in self._listeners:
            redraw()

    def show(self, view: _pictos.View) -> None:
        """Swap in a new view model."""
        self.view = view
        self.changed()

    def say(self, icon: str = "", detail: str = "", *, busy: bool = False) -> None:
        """Set the feedback line (an icon, optional content text, or busy)."""
        self.feedback = Feedback(icon, detail, busy)
        self.changed()

    def spin(self) -> None:
        """Advance the busy spinner one step while something is running."""
        if self.feedback.busy:
            self.phase += 1
            self.changed()
