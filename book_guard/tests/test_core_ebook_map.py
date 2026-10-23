# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_ebook_map: the page map built from located pages."""

from __future__ import annotations

import json
import os
from pathlib import Path

from book_guard._ebook_locate import Knot
from book_guard._ebook_map import PageMap, build_map, page_coordinate
from book_guard._ebook_text import story_bounds
from book_guard.tests._ebook_helpers import (
    PAGE_CHARS,
    STARTS,
    TEXT,
    ocr,
    page_text,
    vocabulary,
)


def test_a_story_opening_with_dialogue_starts_the_map_at_the_text() -> None:
    # Pages 5-30 are short lines (no 200-character paragraph), so the story
    # "starts" after the first photo: the map then starts at offset 0.
    def dialogue(page: int) -> str:
        text = page_text(page).replace(".\n\n", " ")
        return "\n\n".join(text[i : i + 120] for i in range(0, len(text), 120))

    text = "".join(dialogue(p) + "\n\n" for p in range(5, 31))
    text += "".join(page_text(p) + "\n\n" for p in range(31, 60))
    photos = [(9, ocr(9)), (40, ocr(40)), (50, ocr(50))]
    page_map = build_map(text, photos, last_page=59)
    assert page_map is not None
    assert page_map.knots[0].offset == 0
    assert page_map.page_at(0) < 9


def _photos(*pages: int) -> list[tuple[int, str]]:
    return [(p, ocr(p)) for p in pages]


def test_the_map_puts_each_photo_on_its_page() -> None:
    page_map = build_map(TEXT, _photos(9, 30, 51, 77, 100), last_page=120)
    assert page_map is not None
    for page in (9, 30, 51, 77, 100):
        assert page_map.page_at(STARTS[page] + PAGE_CHARS // 2) == page
    for page in (20, 60, 115):  # between and beyond the photos
        assert abs(page_map.page_at(STARTS[page] + PAGE_CHARS // 2) - page) <= 1
    assert page_map.photos == 5
    assert len(page_map.residuals) == 3  # leave-one-out on the inner photos
    assert all(abs(r) < 1 for r in page_map.residuals)


def test_the_map_is_clamped_to_the_book() -> None:
    page_map = build_map(TEXT, _photos(30, 51, 77), last_page=120)
    assert page_map is not None
    start, end = story_bounds(TEXT)
    assert page_map.page_at(0) == page_map.page_at(start)
    assert page_map.page_at(end) == 121  # the end of p. 120: nothing left
    assert page_map.page_at(len(TEXT)) == 121
    assert page_map.shown_page(len(TEXT)) == 120
    assert 1 <= page_map.page_at(start) <= 6


def test_without_a_page_count_the_end_is_extrapolated() -> None:
    page_map = build_map(TEXT, _photos(30, 51, 77), last_page=None)
    assert page_map is not None
    _, end = story_bounds(TEXT)
    assert abs(page_map.page_at(end) - 121) <= 2


def test_fewer_than_three_located_photos_make_no_map() -> None:
    other = " ".join(vocabulary(99)[:250])
    photos = [(30, ocr(30)), (51, ocr(51)), (60, other)]
    assert build_map(TEXT, photos, last_page=120) is None


def test_offset_at_inverts_page_at() -> None:
    page_map = build_map(TEXT, _photos(9, 30, 51, 77, 100), last_page=120)
    assert page_map is not None
    for page in range(6, 121):
        assert page_map.page_at(page_map.offset_at(page)) == page
    assert page_map.offset_at(0) == page_map.knots[0].offset
    assert page_map.offset_at(10_000) == page_map.knots[-1].offset


def test_the_map_round_trips_through_json() -> None:
    page_map = build_map(TEXT, _photos(9, 30, 51, 77), last_page=120)
    assert page_map is not None
    again = PageMap.from_json(json.loads(json.dumps(page_map.to_json())))
    assert again == page_map


def test_a_malformed_map_does_not_load() -> None:
    assert PageMap.from_json({"knots": [[1, 2]]}) is None
    assert PageMap.from_json([]) is None


def test_page_coordinate_interpolates_and_clamps() -> None:
    knots = (Knot(100, 5.0), Knot(300, 7.0), Knot(500, 11.0))
    assert page_coordinate(knots, 0) == 5.0
    assert page_coordinate(knots, 200) == 6.0
    assert page_coordinate(knots, 400) == 9.0
    assert page_coordinate(knots, 900) == 11.0


# The app's Dart port (app/lib/src/ebook_map.dart) must floor the same
# pages from the same map: both sides read this fixture.
FIXTURE = Path(__file__).parents[2] / "app/test/fixtures/ebook_map_goldens.json"


def _goldens() -> dict[str, object]:
    page_map = build_map(TEXT, _photos(9, 30, 51, 77, 100), last_page=120)
    assert page_map is not None
    offsets = sorted({0, len(TEXT), *range(0, len(TEXT), 997)})
    pages = list(range(-1, 125, 3))
    return {
        "map": page_map.to_json(),
        "page_at": [[o, page_map.page_at(o)] for o in offsets],
        "shown_page": [[o, page_map.shown_page(o)] for o in offsets],
        "offset_at": [[p, page_map.offset_at(p)] for p in pages],
    }


def test_the_dart_fixture_is_current() -> None:
    expected = _goldens()
    if os.environ.get("BOOK_GUARD_WRITE_GOLDENS") == "1":
        FIXTURE.write_text(json.dumps(expected, indent=1) + "\n", encoding="utf-8")
    current = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert current == expected, (
        "stale fixture: BOOK_GUARD_WRITE_GOLDENS=1 pytest "
        "book_guard/tests/test_core_ebook_map.py"
    )
