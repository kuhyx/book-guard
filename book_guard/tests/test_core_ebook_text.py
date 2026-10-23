# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_ebook_text: the served text and where the story is in it."""

from __future__ import annotations

from book_guard._ebook_text import served_text, story_bounds
from book_guard.tests._ebook_helpers import FRONT, STARTS, TEXT, page_text


def test_story_bounds_skip_front_and_back_matter() -> None:
    start, end = story_bounds(TEXT)
    assert start == STARTS[5]
    assert TEXT[:end].endswith(page_text(120))


def test_story_bounds_without_back_matter_end_at_the_last_paragraph() -> None:
    text = FRONT + page_text(9) + "\n\n   \n"
    assert story_bounds(text) == (len(FRONT), len(text.rstrip()))


def test_story_bounds_of_a_text_without_long_paragraphs_span_it_all() -> None:
    assert story_bounds("a\n\nb\n\n") == (0, 4)


def test_footnote_back_matter_ends_the_story() -> None:
    text = page_text(9) + "\n\n↑ note one\n\n" + page_text(10)
    _, end = story_bounds(text * 1)
    assert end == len(text)  # the marker is not in the last tenth here
    tail = page_text(9) * 12 + "\n\n↑ note one\n\nmore"
    assert story_bounds(tail)[1] == len(page_text(9) * 12)


def test_served_text_has_no_astral_characters() -> None:
    text = "a\U0001f600b ok"
    served = served_text(text)
    assert served == "a�b ok"
    assert len(served) == len(text)  # offsets are unchanged
    assert len(served.encode("utf-16-le")) // 2 == len(served)  # Dart's view
