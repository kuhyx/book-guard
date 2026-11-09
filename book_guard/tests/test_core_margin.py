# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_margin: a lone patch of ink above or below the text, box-confirmed."""

from __future__ import annotations

from PIL import Image, ImageDraw
import pytest

from book_guard import _margin
from book_guard._ocr import Scan, Word

_WIDTH = 800
_HEIGHT = 1000
_LINE = 16
"""Text-line height: a digit patch is 8-64 px tall, 4x that at most."""
_PAPER = 200
_INK = 90
_BODY_TOP = 300
_BODY_BOTTOM = 600
_BODY = tuple(
    Word(
        "filozofia",
        95.0,
        (100, 300 + 30 * i, 200, 300 + 30 * i + _LINE),
        ("1", "1", str(i)),
    )
    for i in range(10)
)
"""Ten sure words: lines at 300..316 down to 570..586, as tall as ``_LINE``."""


def _page(
    *ink: tuple[int, int, int, int],
    body: tuple[Word, ...] = _BODY,
    ground: int = _PAPER,
) -> Scan:
    """An upright page at the scan's own scale, ``ink`` boxes drawn dark."""
    image = Image.new("L", (_WIDTH, _HEIGHT), ground)
    draw = ImageDraw.Draw(image)
    for box in ink:
        draw.rectangle(box, fill=_INK)
    return Scan(0, (_WIDTH, _HEIGHT), body, "", image)


def _digits(left: int, top: int) -> list[tuple[int, int, int, int]]:
    """Three strokes, 10 px apart: one patch 56 wide and 24 tall."""
    return [(left + 22 * i, top, left + 22 * i + 11, top + 23) for i in range(3)]


def _reads(monkeypatch: pytest.MonkeyPatch, answer: list[int]) -> list[tuple[int, ...]]:
    boxes: list[tuple[int, ...]] = []

    def fake_read_box(_image: Image.Image, box: tuple[int, int, int, int]) -> list[int]:
        boxes.append(box)
        return answer

    monkeypatch.setattr(_margin, "read_box", fake_read_box)
    return boxes


def test_a_pencilled_number_below_the_text_is_found_and_confirmed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # p. 612 of 2026-11-09: three strokes of ink in the empty foot of the page.
    boxes = _reads(monkeypatch, [612])
    assert _margin.margin_candidates(_page(*_digits(100, 800))) == [612]
    # The ink's own box in full pixels, to the shrink's grid (4 px).
    left, top, right, bottom = boxes[0]
    assert left <= 100 <= left + 4
    assert top <= 800 <= top + 4
    assert 156 <= right <= 156 + 4
    assert 824 <= bottom <= 824 + 4


def test_a_number_above_the_text_counts_and_repeats_are_one(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    boxes = _reads(monkeypatch, [7])
    page = _page(*_digits(100, 100), *_digits(300, 800))
    assert _margin.margin_candidates(page) == [7]
    above, below = boxes
    assert 96 <= above[1] <= 100
    assert 796 <= below[1] <= 800


@pytest.mark.parametrize("answer", [[], [1, 2]])
def test_a_crop_that_does_not_read_as_one_number_is_a_smudge(
    monkeypatch: pytest.MonkeyPatch, answer: list[int]
) -> None:
    _reads(monkeypatch, answer)
    assert _margin.margin_candidates(_page(*_digits(100, 800))) == []


def test_a_page_without_real_words_gets_no_third_look(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    boxes = _reads(monkeypatch, [612])
    assert _margin.margin_candidates(_page(*_digits(100, 800), body=_BODY[:9])) == []
    assert boxes == []


def test_a_margin_thinner_than_a_line_is_skipped(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Text from the top edge to the bottom edge: no margin to look in.
    boxes = _reads(monkeypatch, [5])
    tall = (
        Word("filozofia", 95.0, (100, 0, 200, 2 * _LINE), ("1", "1", "0")),
        Word(
            "filozofia", 95.0, (100, _HEIGHT - 2 * _LINE, 200, _HEIGHT), ("1", "1", "1")
        ),
        *_BODY[2:],
    )
    assert _margin.margin_candidates(_page(body=tall)) == []
    assert boxes == []


@pytest.mark.parametrize(
    "ink",
    [
        # Touching the edge of the page: a shadow or the table, not a number.
        [(100, 976, 111, 999)],
        # Dust and a dark band: strokes too small or too big for a glyph.
        [(100, 800, 100, 800)],
        [(100, 700, 400, 760)],
        # A whole word: wider than four digits.
        [(100 + 22 * i, 800, 111 + 22 * i, 823) for i in range(12)],
        # One stroke too short to be a digit.
        [(100, 800, 111, 800)],
        # A patch too tall to be one.
        [(100, 700, 111, 790), (100, 800, 111, 890)],
        # A sliver, not a glyph: thinner than a fifth of its height.
        [(100, 800, 101, 840)],
    ],
)
def test_ink_that_is_no_digit_sized_patch_is_ignored(
    monkeypatch: pytest.MonkeyPatch, ink: list[tuple[int, int, int, int]]
) -> None:
    boxes = _reads(monkeypatch, [5])
    assert _margin.margin_candidates(_page(*ink)) == []
    assert boxes == []


def test_a_patch_with_a_mate_on_its_line_is_no_lone_number(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # "CHINY, 1953": the year has a word beside it, 40 px away.
    boxes = _reads(monkeypatch, [1953])
    page = _page(*_digits(100, 800), *_digits(200, 800))
    assert _margin.margin_candidates(page) == []
    assert boxes == []
    # The same patch with its neighbour on another line is alone.
    page = _page(*_digits(100, 800), *_digits(200, 900))
    assert _margin.margin_candidates(page) == [1953]


def test_ink_off_the_paper_is_ignored(monkeypatch: pytest.MonkeyPatch) -> None:
    # p. 612's carpet, below the page, gave patches that read "1" every time.
    boxes = _reads(monkeypatch, [1])
    image = _page(*_digits(100, 800)).image
    ImageDraw.Draw(image).rectangle((0, 700, _WIDTH - 1, _HEIGHT - 1), fill=60)
    ImageDraw.Draw(image).rectangle((100, 800, 111, 823), fill=10)
    page = Scan(0, (_WIDTH, _HEIGHT), _BODY, "", image)
    assert _margin.margin_candidates(page) == []
    assert boxes == []


def test_a_busy_margin_is_no_lone_number(monkeypatch: pytest.MonkeyPatch) -> None:
    boxes = _reads(monkeypatch, [5])
    rows = [box for row in range(5) for box in _digits(100, 650 + 60 * row)]
    assert _margin.margin_candidates(_page(*rows)) == []
    assert boxes == []


def test_the_scan_may_be_smaller_than_the_image(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Words are in the scanned page's pixels; the image is twice as big.
    boxes = _reads(monkeypatch, [3])
    page = _page(*_digits(200, 1600))
    big = Image.new("L", (2 * _WIDTH, 2 * _HEIGHT), _PAPER)
    ImageDraw.Draw(big).rectangle((200, 1600, 211, 1623), fill=_INK)
    ImageDraw.Draw(big).rectangle((222, 1600, 233, 1623), fill=_INK)
    scaled = Scan(0, page.size, _BODY, "", big)
    assert _margin.margin_candidates(scaled) == [3]
    assert boxes[0][0] == 200


def test_without_any_ink_there_is_nothing(monkeypatch: pytest.MonkeyPatch) -> None:
    _reads(monkeypatch, [5])
    assert _margin.margin_candidates(_page()) == []
