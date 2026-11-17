# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The end-evening control: an icon, no words, visible from the first frame."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from book_guard import _evening_view, _icons
from book_guard import _pictos as p

if TYPE_CHECKING:
    import pytest


class _Canvas:
    def __init__(self) -> None:
        self.placed: dict[str, Any] = {}
        self.bindings: dict[str, Any] = {}

    def place(self, **kwargs: Any) -> None:
        self.placed = kwargs

    def bind(self, sequence: str, callback: Any) -> None:
        self.bindings[sequence] = callback

    def configure(self, **_kwargs: Any) -> None:
        """Cursor styling: not under test."""


def test_end_control_is_an_icon_in_the_corner_that_ends_the_evening(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    made: list[tuple[Any, str]] = []
    canvas = _Canvas()

    def icon(parent: Any, name: str, **_kwargs: Any) -> _Canvas:
        made.append((parent, name))
        return canvas

    monkeypatch.setattr(_evening_view, "icon", icon)
    ended: list[bool] = []
    parent: Any = "parent"
    _evening_view.add_end_control(parent, lambda: ended.append(True))
    assert made == [("parent", p.END)]
    assert canvas.placed == {"relx": 0.98, "rely": 0.02, "anchor": "ne"}
    canvas.bindings["<Button-1>"](object())
    assert ended == [True]


def test_both_new_icons_are_drawn_and_have_a_glyph() -> None:
    for name in (p.MOON, p.END):
        assert name in _icons.SHAPES
        assert name in p.GLYPH
