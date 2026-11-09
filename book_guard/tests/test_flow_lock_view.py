# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The lock's widgets, built against a recording stand-in for ``tkinter``.

No display is needed (or touched): ``tk`` in the view modules is swapped for
a namespace whose widget classes record how they were built, packed and
bound, and whose bound callbacks the tests then fire. The key check is that
no widget carries a word: only icons, numbers, and user content.
"""

from __future__ import annotations

from dataclasses import replace
import re
from types import SimpleNamespace
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _lock_paint, _lock_view, _pictos
from book_guard._lock_paint import BG
from book_guard._lock_view import (
    build_inputs,
    build_status,
    install_demo_close,
    make_vars,
)
from book_guard._sessions import NEEDS_CHECK, NEEDS_QUIZ
from book_guard._state import SessionView
from book_guard.tests._flow_helpers import make_book, make_snap
from book_guard.tests.test_flow_render import CHECK

if TYPE_CHECKING:
    from collections.abc import Callable

_VERDICTS: Any = (object(),)
WORD = re.compile(r"[A-Za-z]{2,}")


class _Widget:
    """Any Tk widget: remembers its construction, children and drawing."""

    built: list[_Widget]

    def __init__(self, master: Any = None, **kwargs: Any) -> None:
        self.kind = type(self).__name__
        self.master = master
        self.kwargs = kwargs
        self.children: list[_Widget] = []
        self.drawn: list[str] = []
        self.geometry: tuple[str, dict[str, Any]] | None = None
        self.bindings: dict[str, Callable[[object], None]] = {}
        self.config: dict[str, Any] = {}
        self.content = ""
        self.built.append(self)
        if isinstance(master, _Widget):
            master.children.append(self)

    def pack(self, **kwargs: Any) -> None:
        self.geometry = ("pack", kwargs)

    def place(self, **kwargs: Any) -> None:
        self.geometry = ("place", kwargs)

    def bind(self, sequence: str, callback: Callable[[object], None]) -> None:
        self.bindings[sequence] = callback

    def configure(self, options: dict[str, Any]) -> None:
        self.config.update(options)

    def winfo_children(self) -> list[_Widget]:
        return list(self.children)

    def destroy(self) -> None:
        if isinstance(self.master, _Widget):
            self.master.children.remove(self)

    def get(self, *_index: str) -> str:
        return self.content

    def __getattr__(self, name: str) -> Callable[..., None]:
        if not name.startswith("create_"):
            raise AttributeError(name)
        return lambda *_a, **_k: self.drawn.append(name)


ROOT: Any = object()


@pytest.fixture
def fake_tk(monkeypatch: pytest.MonkeyPatch) -> Any:
    """A ``tkinter`` stand-in; ``fake_tk.log`` lists every widget built."""
    log: list[Any] = []
    names = ("Label", "Frame", "Text", "Button", "Entry", "Canvas")
    fake = SimpleNamespace(
        log=log, **{name: type(name, (_Widget,), {"built": log}) for name in names}
    )
    for module in (_lock_view, _lock_paint):
        monkeypatch.setattr(module, "tk", fake)
    return fake


def _busy_snap() -> Any:
    sessions = [SessionView(CHECK, None, NEEDS_CHECK)]
    sessions.append(SessionView(CHECK, None, NEEDS_QUIZ, verdicts=_VERDICTS))
    return replace(make_snap(book=make_book()), sessions=sessions)


def _words(fake_tk: Any, *, allow: tuple[str, ...] = ()) -> list[str]:
    found = []
    for w in fake_tk.log:
        text = w.kwargs.get("text", "")
        if WORD.search(text) and text not in allow:
            found.append(text)
    return found


def test_make_vars_is_plain_shared_state() -> None:
    shared = make_vars(ROOT)
    assert shared.view is None
    assert shared.feedback.icon == ""


def test_build_status_draws_icons_and_numbers_only(fake_tk: Any) -> None:
    parent = fake_tk.Frame(ROOT)
    shared = make_vars(ROOT)
    column: Any = build_status(parent, shared)
    assert parent.config == {"bg": BG}
    assert column.geometry == (
        "place",
        {"relx": 0.5, "rely": 0.5, "anchor": "center"},
    )
    before = len(fake_tk.log)
    shared.show(_pictos.build(_busy_snap()))
    assert len(fake_tk.log) > before
    canvases = [w for w in fake_tk.log if w.kind == "Canvas"]
    assert canvases
    assert any(w.drawn for w in canvases)
    # Only the book's title is a word: user content.
    assert _words(fake_tk) == [f"{make_book().label}  ▤300"]


def test_status_repaint_replaces_the_old_widgets(fake_tk: Any) -> None:
    shared = make_vars(ROOT)
    column: Any = build_status(fake_tk.Frame(ROOT), shared)
    body = column.children[0]
    shared.show(_pictos.build(_busy_snap()))
    first = body.winfo_children()
    shared.show(_pictos.build(_busy_snap()))
    assert body.winfo_children() != first
    assert len(body.winfo_children()) == len(first)


def test_build_inputs_wires_both_callbacks(fake_tk: Any) -> None:
    shared = make_vars(ROOT)
    shared.show(_pictos.build(_busy_snap()))
    column = fake_tk.Frame(ROOT)
    fired: list[str] = []
    widgets: Any = build_inputs(
        column,
        shared,
        on_submit=lambda: fired.append("submit"),
        on_escape=lambda: fired.append("escape"),
    )
    shared.show(_pictos.build(_busy_snap()))  # a repaint after the inputs exist
    widgets.summary.bindings["<Control-Return>"](object())
    widgets.submit.kwargs["command"]()
    widgets.escape.bindings["<Return>"](object())
    assert fired == ["submit", "submit", "escape"]
    assert widgets.submit.kwargs["text"] == "✓"
    assert _words(fake_tk) == []


def test_length_bar_fills_with_the_summary(fake_tk: Any) -> None:
    shared = make_vars(ROOT)
    widgets: Any = build_inputs(
        fake_tk.Frame(ROOT), shared, on_submit=print, on_escape=print
    )
    gauge = widgets.summary.master.children[-1]
    assert gauge.kind == "Frame"
    widgets.summary.content = "x" * 200
    widgets.summary.bindings["<KeyRelease>"](object())
    assert any(w.kwargs.get("text") is None for w in gauge.children)
    widgets.summary.content = ""
    widgets.meter()


@pytest.mark.parametrize(
    ("icon", "detail", "busy"),
    [
        ("", "", True),
        (_pictos.OK, "", False),
        (_pictos.NO, "- the ending", False),
        (_pictos.WARN, "", False),
    ],
)
def test_feedback_is_an_icon_a_spinner_or_content(
    fake_tk: Any, icon: str, detail: str, *, busy: bool
) -> None:
    shared = make_vars(ROOT)
    widgets: Any = build_inputs(
        fake_tk.Frame(ROOT), shared, on_submit=print, on_escape=print
    )
    shared.say(icon, detail, busy=busy)
    row = [w for w in fake_tk.log if w.kind == "Frame"][-3]
    texts = [w.kwargs.get("text") for w in row.children if w.kind == "Label"]
    if busy:
        assert texts == [_lock_paint.SPINNER[0]]
        shared.spin()
        assert shared.phase == 1
    else:
        assert texts == ([detail] if detail else [])
    assert widgets.escape.kwargs["highlightbackground"] == _lock_paint.DANGER


def test_spin_only_moves_while_busy() -> None:
    shared = make_vars(ROOT)
    shared.spin()
    assert shared.phase == 0


def test_demo_close_button(fake_tk: Any) -> None:
    closed: list[bool] = []
    install_demo_close(ROOT, lambda: closed.append(True))
    (button,) = fake_tk.log
    assert button.master is ROOT
    assert button.kwargs["text"] == "✕"
    assert button.geometry == ("place", {"relx": 0.98, "rely": 0.02, "anchor": "ne"})
    button.kwargs["command"]()
    assert closed == [True]


def test_icon_canvas_draws_every_primitive(fake_tk: Any) -> None:
    for name in _pictos.GLYPH:
        canvas: Any = _lock_paint.icon(fake_tk.Frame(ROOT), name, size=24)
        assert canvas.drawn, name


def test_done_gauge_gets_a_tick_and_a_sick_day_an_empty_bar(fake_tk: Any) -> None:
    shared = make_vars(ROOT)
    column: Any = build_status(fake_tk.Frame(ROOT), shared)
    snap = make_snap(book=make_book())
    snap = replace(
        snap,
        sick_days=frozenset({snap.today}),
        pace=replace(snap.pace, pages=snap.pace.required),
    )
    shared.show(_pictos.build(snap))
    body = column.children[0]
    rows = [w for w in body.children if w.kind == "Frame"]
    assert any(c.drawn for r in rows for c in r.children if c.kind == "Canvas")
