# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_pencil_find: the pencilled number in a margin, read by the digit net."""

from __future__ import annotations

import base64
import json
import os
from pathlib import Path
from typing import TYPE_CHECKING, cast
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from book_guard import _pencil_find as find
from book_guard._patch import Patch
from book_guard._pencil_net import load
from book_guard._pencil_norm import normalise

if TYPE_CHECKING:
    import pytest

    from book_guard._pencil_net import Net

FIXTURE = Path(__file__).parents[2] / "app/test/fixtures/pencil_goldens.json"
_LINE = 16.0
_BODY = (100, 300, 700, 600)


def _page(
    *strokes: list[tuple[int, int]],
    ink: int = 140,
    size: tuple[int, int] = (800, 1000),
) -> np.ndarray:
    """Paper 200, pencil strokes (3 px, softly blurred) of grey ``ink``."""
    image = Image.new("L", size, 200)
    draw = ImageDraw.Draw(image)
    for points in strokes:
        draw.line(points, fill=ink, width=3)
    return np.asarray(image.filter(ImageFilter.GaussianBlur(1.0)))


def _one(x: int, y: int) -> list[list[tuple[int, int]]]:
    """A European one: a stem and a flag."""
    return [[(x, y), (x, y + 40)], [(x, y), (x - 10, y + 12)]]


def _seven(x: int, y: int) -> list[list[tuple[int, int]]]:
    return [[(x - 10, y), (x + 8, y), (x - 6, y + 40)]]


def _number(gray: np.ndarray) -> int | None:
    return find.find_number(load(), gray, _BODY, _LINE)


def test_the_goldens_are_the_finders_answers() -> None:
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    for case in fixture["cases"]:
        raw = zlib.decompress(base64.b64decode(case["gray"]))
        gray = np.frombuffer(raw, np.uint8).reshape(case["height"], case["width"])
        got = find.find_number(load(), gray, tuple(case["body"]), case["line"])
        assert got == case["expected"], case["name"]
        assert os.environ.get("BOOK_GUARD_WRITE_GOLDENS") != "1"


def test_a_pencilled_one_or_seven_below_or_above_the_text_is_read() -> None:
    assert _number(_page(*_one(150, 800))) == 1
    assert _number(_page(*_one(150, 100))) == 1
    assert _number(_page(*_seven(150, 800))) == 7


def test_a_two_glyph_number_is_read_as_one_patch() -> None:
    assert _number(_page(*_one(150, 800), *_seven(172, 800))) == 17


def test_two_different_numbers_are_ambiguous_and_the_same_twice_is_one() -> None:
    assert _number(_page(*_one(150, 100), *_seven(150, 800))) is None
    assert _number(_page(*_one(150, 100), *_one(150, 800))) == 1


def test_print_dark_ink_is_no_pencil_and_a_faint_shadow_is_no_number() -> None:
    assert _number(_page(*_one(150, 800), ink=60)) is None
    assert _number(_page(*_one(150, 800), ink=178)) is None


def test_ink_beside_other_ink_on_its_line_is_not_alone() -> None:
    assert _number(_page(*_one(150, 800), *_one(200, 800))) is None


def test_a_margin_thinner_than_a_line_has_nothing_to_read() -> None:
    gray = _page(*_one(150, 800))
    assert find.find_number(load(), gray, (100, 300, 700, 990), _LINE) is None


def test_a_dark_ground_is_no_paper() -> None:
    gray = _page(*_one(150, 800)).copy()
    gray[700:, :] //= 3  # the carpet below the page
    assert _number(gray) is None


def test_more_than_four_lone_patches_is_a_busy_margin() -> None:
    strokes = [s for i in range(5) for s in _one(120 + 120 * i, 800)]
    assert _number(_page(*strokes)) is None


class _Scripted:
    """A network that answers with the next scripted probability vector."""

    def __init__(self, *answers: list[float]) -> None:
        self._answers = [np.array(a) for a in answers]

    def probabilities(self, picture: np.ndarray) -> np.ndarray:
        del picture
        return self._answers.pop(0)


def _net(*answers: list[float]) -> Net:
    return cast("Net", _Scripted(*answers))


def _sure(digit: int, share: float = 0.9) -> list[float]:
    probs = [(1 - share) / 10] * 11
    probs[digit] = share
    return probs


_MASK = np.ones((20, 4), dtype=bool)


def test_a_glyph_is_a_digit_only_when_every_width_agrees_and_is_sure() -> None:
    three = [_sure(4)] * 3
    assert find._digit(_net(*three), _MASK) == 4
    assert find._digit(_net(_sure(4), _sure(5), _sure(4)), _MASK) is None
    assert find._digit(_net(*[_sure(10)] * 3), _MASK) is None
    assert find._digit(_net(*[_sure(4, 0.5)] * 3), _MASK) is None


def test_a_number_is_its_digits_never_empty_long_or_led_by_zero(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    diff = np.full((60, 60), 40.0)
    glyph = Patch(5, 5, 20, 50)

    def read(*digits: int | None) -> int | None:
        queue = list(digits)
        monkeypatch.setattr(find, "_digit", lambda *_a: queue.pop(0))
        return find._read(load(), diff, [glyph] * len(digits))

    assert read(6, 1, 2) == 612
    assert read() is None
    assert read(1, 2, 3, 4, 5) is None
    assert read(0, 5) is None
    assert read(6, None) is None


def test_the_glyph_mask_is_cut_tight_to_what_is_darker_than_its_own_peak() -> None:
    diff = np.zeros((40, 40))
    diff[10:30, 15:17] = 50.0  # the stroke
    diff[12, 20] = 15.0  # a faint speck, below 0.4 of the peak
    mask = find.glyph_mask(diff, Patch(14, 9, 18, 31))
    assert mask.shape == (20, 2)
    assert normalise(mask, 0.14).sum() > 0


def test_a_pencil_smudge_that_is_no_digit_gives_nothing() -> None:
    zigzag = [(150, 800), (170, 806), (150, 812), (172, 818), (150, 824), (170, 830)]
    assert _number(_page(zigzag)) is None


def test_a_text_box_outside_the_page_is_clipped_or_gives_nothing() -> None:
    gray = _page(*_one(150, 800))
    assert find.find_number(load(), gray, (100, 300, 700, 5000), _LINE) is None
    assert find.find_number(load(), gray, (2000, 300, 2500, 600), _LINE) is None
    assert find.find_number(load(), gray, (100, 3000, 700, 4000), _LINE) is None
