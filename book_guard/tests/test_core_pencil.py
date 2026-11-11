# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_pencil: the public reader, from a scanned page or a photo."""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from PIL import Image, ImageDraw, ImageFilter

from book_guard import _pencil
from book_guard._ocr import Scan, Word

if TYPE_CHECKING:
    import pytest

_LINE = 16
_WORDS = tuple(
    Word(
        "filozofia",
        95.0,
        (100, 300 + 30 * i, 200, 300 + 30 * i + _LINE),
        ("1", "1", str(i)),
    )
    for i in range(10)
)


def _page(words: tuple[Word, ...] = _WORDS) -> Scan:
    """An upright page: a pencilled European one in the foot, paper 200."""
    image = Image.new("L", (800, 1000), 200)
    draw = ImageDraw.Draw(image)
    draw.line([(150, 800), (150, 840)], fill=140, width=3)
    draw.line([(150, 800), (140, 812)], fill=140, width=3)
    return Scan(0, (800, 1000), words, "", image.filter(ImageFilter.GaussianBlur(1.0)))


def test_a_scanned_page_with_a_pencilled_one_gives_one() -> None:
    assert _pencil.read_pencil_page(_page()) == 1


def test_a_page_that_may_be_turned_is_not_read() -> None:
    # Too few sure words: the turn is unknown and a 6 is a 9 upside down.
    assert _pencil.read_pencil_page(_page(_WORDS[:3])) is None


def test_a_photo_is_scanned_first(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        _pencil, "scan", lambda path: _page() if path.name == "a.jpg" else None
    )
    assert _pencil.read_pencil(Path("a.jpg")) == 1
    assert _pencil.read_pencil(Path("unreadable.jpg")) is None


def test_the_facing_pages_text_does_not_stretch_the_body() -> None:
    facing = tuple(
        Word(
            "sztuka",
            95.0,
            (5, 100 + 30 * i, 60, 100 + 30 * i + _LINE),
            ("1", "1", str(i)),
        )
        for i in range(3)
    )
    page = _page(facing + _WORDS)
    assert _pencil.column_body(page) == ((100, 300, 200, 586), _LINE)
