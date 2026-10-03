# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_pagenum: candidates by position, choice by plausibility, boxes."""

from __future__ import annotations

import io
import subprocess

from PIL import Image, ImageOps
import pytest

from book_guard import _pagenum
from book_guard._ocr import Scan, Word
from book_guard._pagenum import Choice, Context, choose
from book_guard.tests.test_core_ocr import tsv


def _word(text: str, top: int, line: str, conf: float = 95.0) -> Word:
    return Word(text, conf, (40, top, 50, top + 10), (line, "1", "1"))


def test_candidates_are_lone_numbers_near_an_edge() -> None:
    page = Scan(
        rotation=0,
        size=(100, 1000),
        words=(
            _word("3", 50, "1"),  # chapter numeral, top band
            _word("1953", 120, "2"),  # alone but a year in a heading: in band
            _word("Pasmo", 500, "3"),
            _word("12", 500, "4"),  # mid-page: not a page number
            _word("w", 950, "5"),
            _word("19", 950, "5"),  # shares a line
            _word("51", 960, "6"),
            _word("51", 965, "7"),  # duplicate
            _word("99", 970, "8", conf=30.0),  # unsure
            _word("12345", 980, "9"),  # too long
        ),
        text="",
        image=Image.new("L", (1, 1)),
    )
    assert _pagenum.candidates(page) == [3, 1953, 51]


@pytest.mark.parametrize(
    ("found", "context", "expected"),
    [
        ([3, 19], Context(expected=19), Choice(19)),
        ([3], Context(expected=19), Choice(None, "page 19 not found on the photo")),
        ([], Context(), Choice(None, "no page number found")),
        ([3], Context(after=7), Choice(None, "no page after 7 found on the photo")),
        ([3, 51], Context(after=7, last_page=406), Choice(51)),
        ([51, 80], Context(after=7), Choice(None, "page number unclear (51 or 80)")),
        ([500], Context(last_page=406), Choice(None, "no page number found")),
        ([51], Context(), Choice(51)),
        ([3, 51], Context(near=51), Choice(51)),
        ([3, 51], Context(near=27), Choice(None, "page number unclear (3 or 51)")),
        ([3, 51], Context(near=51, hint=3), Choice(3)),
        ([3], Context(near=51), Choice(None, "page 3 is far from p. 51, the last one")),
        ([45], Context(near=51), Choice(45)),
    ],
)
def test_choose(found: list[int], context: Context, expected: Choice) -> None:
    assert choose(found, context) == expected


def test_a_boxed_far_start_is_believed() -> None:
    assert choose([3], Context(near=51), boxed=True) == Choice(3)


@pytest.mark.parametrize("orientation", [1, 2, 3, 4, 5, 6, 7, 8])
@pytest.mark.parametrize("rotation", [0, 90, 180, 270])
def test_upright_box_follows_exif_and_rotation(orientation: int, rotation: int) -> None:
    """A dot boxed in the stored pixels is where PIL puts it upright."""
    stored = Image.new("L", (60, 40), 255)
    stored.putpixel((10, 5), 0)
    exif = stored.getexif()
    exif[0x0112] = orientation
    reloaded = _roundtrip(stored, exif)
    box = _pagenum.upright_box(reloaded, (10, 5, 11, 6), rotation)
    upright = ImageOps.exif_transpose(reloaded).rotate(rotation, expand=True)
    assert box is not None
    dark = [
        (x, y)
        for x in range(upright.width)
        for y in range(upright.height)
        if upright.getpixel((x, y)) == 0
    ]
    assert dark
    assert all(box[0] <= x < box[2] and box[1] <= y < box[3] for x, y in dark)


def _roundtrip(image: Image.Image, exif: Image.Exif) -> Image.Image:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", exif=exif)
    buffer.seek(0)
    return Image.open(buffer)


def test_read_box_reads_digits_in_the_crop(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[list[str]] = []

    def run(argv: list[str], **_kw: object) -> subprocess.CompletedProcess[bytes]:
        calls.append(argv)
        out = tsv(("1", 0, 0, 5, 5, 91.0, "5"), ("1", 6, 0, 5, 5, 92.0, "1"))
        return subprocess.CompletedProcess(argv, 0, stdout=out.encode())

    monkeypatch.setattr("book_guard._ocr.shutil.which", lambda n: f"/usr/bin/{n}")
    monkeypatch.setattr("book_guard._ocr.subprocess.run", run)
    gray = Image.new("L", (100, 100), 255)
    assert _pagenum.read_box(gray, (40, 40, 60, 50)) == [51]
    assert "tessedit_char_whitelist=0123456789" in calls[0]


def test_read_box_nothing_legible(monkeypatch: pytest.MonkeyPatch) -> None:
    def run(argv: list[str], **_kw: object) -> subprocess.CompletedProcess[bytes]:
        out = tsv(("1", 0, 0, 5, 5, 20.0, "7"))
        return subprocess.CompletedProcess(argv, 0, stdout=out.encode())

    monkeypatch.setattr("book_guard._ocr.shutil.which", lambda n: f"/usr/bin/{n}")
    monkeypatch.setattr("book_guard._ocr.subprocess.run", run)
    assert _pagenum.read_box(Image.new("L", (50, 50), 255), (0, 0, 10, 10)) == []
