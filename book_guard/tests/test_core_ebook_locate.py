# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_ebook_locate: finding a photographed page in the ebook text."""

from __future__ import annotations

import pytest

from book_guard._ebook_locate import MIN_Z, Knot, StemIndex, knots_from, locate
from book_guard.tests._ebook_helpers import (
    PAGE_CHARS,
    STARTS,
    TEXT,
    VOCAB,
    ocr,
    page_text,
    vocabulary,
)


def test_each_photographed_page_is_located_near_its_page() -> None:
    index = StemIndex(TEXT)
    for page in (9, 42, 77, 110):
        found = locate(index, ocr(page))
        assert found is not None
        offset, z = found
        middle = STARTS[page] + PAGE_CHARS // 2
        assert abs(offset - middle) < PAGE_CHARS * 0.6, page
        assert z > MIN_Z


def test_a_page_from_another_book_does_not_locate() -> None:
    index = StemIndex(TEXT)
    other = " ".join(vocabulary(99)[:250])
    found = locate(index, other)
    assert found is None or found[1] < MIN_Z


def test_too_little_text_does_not_locate() -> None:
    assert locate(StemIndex(TEXT), "a b c") is None


def test_a_text_where_every_window_scores_alike_does_not_locate() -> None:
    words = " ".join(VOCAB[:12])
    assert locate(StemIndex((words + " ") * 300), words) is None


def test_a_photo_of_page_zero_is_no_knot() -> None:
    assert knots_from([(0, 500.0, 20.0)]) == ()


def test_a_text_too_short_for_one_window_has_one_window() -> None:
    index = StemIndex(page_text(3))
    assert locate(index, ocr(3)) is None  # one window: no spread, no z


def test_knots_average_duplicates_and_drop_out_of_order_outliers() -> None:
    located = [
        (10, 15_000.0, 12.0),
        (10, 15_100.0, 14.0),
        (20, 30_000.0, 12.0),
        (25, 2_000.0, 15.0),  # wrong chapter: breaks the order
        (30, 45_000.0, 11.0),
        (40, 60_000.0, 3.0),  # too weak
    ]
    knots = knots_from(located)
    assert knots == (
        Knot(15_050, 10.5),
        Knot(30_000, 20.5),
        Knot(45_000, 30.5),
    )


def test_an_ambiguous_tie_keeps_the_stronger_chain() -> None:
    located = [(10, 10_000.0, 12.0), (20, 5_000.0, 30.0), (30, 30_000.0, 12.0)]
    # Both (10, 30) and (20, 30) are 2 long: the stronger z sum wins.
    assert [k.page for k in knots_from(located)] == [20.5, 30.5]


@pytest.mark.parametrize("bad", ["", "x" * 10])
def test_an_empty_or_tiny_text_has_no_index_windows_to_score(bad: str) -> None:
    assert locate(StemIndex(bad), ocr(30)) is None
