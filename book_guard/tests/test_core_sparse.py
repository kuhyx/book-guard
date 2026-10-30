# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_sparse: a page number set between ornaments, read sparse, box-confirmed."""

from __future__ import annotations

from PIL import Image
import pytest

from book_guard import _sparse
from book_guard._ocr import Scan, Word
from book_guard.tests.test_core_ocr import tsv

_BODY = tuple(
    Word("filozofia", 95.0, (10, 300, 60, 310), ("9", "1", str(i))) for i in range(10)
)


def _page(body: tuple[Word, ...] = _BODY) -> Scan:
    """A scan at half the full image's resolution, upright by its body text."""
    return Scan(
        rotation=0,
        size=(100, 1000),
        words=body,
        text="",
        image=Image.new("L", (200, 2000), 255),
    )


def test_a_number_between_swashes_is_found_and_confirmed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The p. 9 opener of 2026-10-30 as psm 11 read it: "z 9 s" at the foot.
    calls: list[tuple[str, ...]] = []

    def fake_tesseract(image: Image.Image, *args: str) -> str:
        calls.append(args)
        assert image.size == (100, 1000)  # the main reading's scale
        return tsv(
            ("1", 30, 900, 15, 30, 32.0, "z"),
            ("1", 50, 900, 5, 30, 89.0, "9"),
            ("1", 60, 900, 15, 30, 55.0, "s”"),
            ("2", 10, 100, 30, 10, 92.0, "CHINY,"),  # a heading with a year
            ("2", 45, 100, 10, 10, 96.0, "1953"),
            ("3", 40, 500, 10, 10, 97.0, "12"),  # mid-page
            ("4", 40, 950, 10, 10, 40.0, "77"),  # unsure itself
        )

    boxes: list[tuple[int, int, int, int]] = []

    def fake_read_box(_image: Image.Image, box: tuple[int, int, int, int]) -> list[int]:
        boxes.append(box)
        return [9]

    monkeypatch.setattr(_sparse, "tesseract", fake_tesseract)
    monkeypatch.setattr(_sparse, "read_box", fake_read_box)
    assert _sparse.sparse_candidates(_page()) == [9]
    assert calls == [("-l", "pol", "--psm", "11", "tsv")]  # never psm 12
    assert boxes == [(100, 1800, 110, 1860)]  # in the full image's pixels


@pytest.mark.parametrize("box_reads", [[9, 6], [6], []])
def test_a_box_that_does_not_read_unanimously_is_no_candidate(
    monkeypatch: pytest.MonkeyPatch, box_reads: list[int]
) -> None:
    # A 9 read upside down is a 6: any spread in the crop is not a page.
    monkeypatch.setattr(
        _sparse,
        "tesseract",
        lambda _image, *_args: tsv(("1", 50, 900, 5, 30, 89.0, "9")),
    )
    monkeypatch.setattr(_sparse, "read_box", lambda _image, _box: box_reads)
    assert _sparse.sparse_candidates(_page()) == []


def test_without_tesseract_there_is_nothing() -> None:
    # conftest hides every binary: the real wrapper answers "".
    assert _sparse.sparse_candidates(_page()) == []


def test_a_page_without_real_words_gets_no_second_look(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Turned the wrong way as a whole, the 9 reads 6 under every setting:
    # only the body text says the turn is wrong (0-3 sure words, not 28+).
    def no_tesseract(*_args: object) -> str:
        raise AssertionError

    monkeypatch.setattr(_sparse, "tesseract", no_tesseract)
    unsure = tuple(Word(w.text, 79.0, w.box, w.line) for w in _BODY)
    short = tuple(Word("ab", 95.0, w.box, w.line) for w in _BODY)
    digits = tuple(Word("1953", 95.0, w.box, w.line) for w in _BODY)
    for body in (_BODY[:9], unsure, short, digits):
        assert _sparse.sparse_candidates(_page(body)) == []
