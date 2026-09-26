# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The lock's widgets, built against a recording stand-in for ``tkinter``.

No display is needed (or touched): ``book_guard._lock_view.tk`` is swapped for
a namespace whose widget classes record how they were built, packed, placed
and bound, and whose bound callbacks the tests then fire.
"""

from __future__ import annotations

from types import SimpleNamespace
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _lock_view
from book_guard._lock_view import (
    ACCENT,
    BG,
    DANGER,
    MUTED,
    WRAP_PX,
    build_inputs,
    build_status,
    install_demo_close,
    make_vars,
)

if TYPE_CHECKING:
    from collections.abc import Callable


class _Widget:
    """Any Tk widget or variable: remembers its construction and geometry."""

    built: list[_Widget]

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        self.kind = type(self).__name__
        self.args = args
        self.kwargs = kwargs
        self.geometry: tuple[str, dict[str, Any]] | None = None
        self.bindings: dict[str, Callable[[object], None]] = {}
        self.config: dict[str, Any] = {}
        self.built.append(self)

    def pack(self, **kwargs: Any) -> None:
        self.geometry = ("pack", kwargs)

    def place(self, **kwargs: Any) -> None:
        self.geometry = ("place", kwargs)

    def bind(self, sequence: str, callback: Callable[[object], None]) -> None:
        self.bindings[sequence] = callback

    def configure(self, options: dict[str, Any]) -> None:
        self.config.update(options)


ROOT: Any = object()
"""The Tk master the variables are created on; the fakes only record it."""


@pytest.fixture
def fake_tk(monkeypatch: pytest.MonkeyPatch) -> Any:
    """A ``tkinter`` stand-in; ``fake_tk.log`` lists every widget built."""
    log: list[Any] = []
    names = ("StringVar", "Label", "Frame", "Text", "Button", "Entry")
    fake = SimpleNamespace(
        log=log, **{name: type(name, (_Widget,), {"built": log}) for name in names}
    )
    monkeypatch.setattr(_lock_view, "tk", fake)
    return fake


def test_make_vars_masters_every_var_on_the_root(fake_tk: Any) -> None:
    shared = make_vars(ROOT)
    built: list[Any] = fake_tk.log
    assert [w.kind for w in built] == ["StringVar"] * 4
    assert all(w.kwargs == {"master": ROOT} for w in built)
    assert shared.feedback is built[3]


def test_build_status(fake_tk: Any) -> None:
    parent = fake_tk.Frame(ROOT)
    fake_tk.log.clear()
    shared = make_vars(ROOT)
    column = build_status(parent, shared)
    assert parent.config == {"bg": BG}
    frame, title, status, todo = fake_tk.log[4:]
    assert frame.geometry == ("place", {"relx": 0.5, "rely": 0.5, "anchor": "center"})
    assert column is frame  # after: an identity check narrows frame to tk.Frame
    assert title.kwargs["text"] == "Read your book"
    assert title.kwargs["fg"] == ACCENT
    assert status.kwargs["textvariable"] is shared.status
    assert status.kwargs["wraplength"] == WRAP_PX
    assert todo.kwargs["fg"] == ACCENT
    assert todo.geometry == ("pack", {"anchor": "w", "pady": (0, 16)})


def test_build_inputs_wires_both_callbacks(fake_tk: Any) -> None:
    shared = make_vars(ROOT)
    column = fake_tk.Frame(ROOT)
    fired: list[str] = []
    widgets: Any = build_inputs(
        column,
        shared,
        on_submit=lambda: fired.append("submit"),
        on_escape=lambda: fired.append("escape"),
    )
    built: list[Any] = fake_tk.log[5:]
    assert [w.kind for w in built] == [
        "Label",
        "Text",
        "Button",
        "Label",
        "Label",
        "Entry",
    ]
    quiz_title, _text, _button, feedback, hint, _entry = built
    assert quiz_title.kwargs["fg"] == MUTED
    assert feedback.kwargs["textvariable"] is shared.feedback
    assert feedback.kwargs["fg"] == DANGER
    assert hint.geometry == ("pack", {"anchor": "w", "pady": (24, 4)})
    widgets.summary.bindings["<Control-Return>"](object())
    widgets.submit.kwargs["command"]()
    widgets.escape.bindings["<Return>"](object())
    assert fired == ["submit", "submit", "escape"]


def test_demo_close_button(fake_tk: Any) -> None:
    closed: list[bool] = []
    install_demo_close(ROOT, lambda: closed.append(True))
    (button,) = fake_tk.log
    assert button.args == (ROOT,)
    assert button.kwargs["text"] == "Close demo"
    assert button.geometry == ("place", {"relx": 0.98, "rely": 0.02, "anchor": "ne"})
    button.kwargs["command"]()
    assert closed == [True]
