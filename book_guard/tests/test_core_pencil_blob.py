# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_pencil_blob: ink runs, patches and glyphs."""

from __future__ import annotations

import numpy as np

from book_guard._patch import Patch
from book_guard._pencil_blob import Blob, blobs, merge_glyphs, patches

_UNIT = 10.0


def _ink(
    *boxes: tuple[int, int, int, int], size: tuple[int, int] = (80, 120)
) -> np.ndarray:
    """``boxes`` (left, top, right, bottom, inclusive) as ink on an empty field."""
    ink = np.zeros(size, dtype=bool)
    for left, top, right, bottom in boxes:
        ink[top : bottom + 1, left : right + 1] = True
    return ink


def _blobs(ink: np.ndarray, busy: float = 0.5) -> list[Blob]:
    return blobs(ink, (0, ink.shape[0], 0, ink.shape[1]), _UNIT, busy)


def _blob(left: int, top: int, right: int, bottom: int) -> Blob:
    empty = np.zeros(0, dtype=np.intp)
    return Blob(Patch(left, top, right, bottom), empty, empty)


def test_a_run_is_found_with_its_box_in_the_whole_images_pixels() -> None:
    ink = _ink((30, 20, 33, 45))
    found = blobs(ink, (10, 70, 20, 100), _UNIT, 0.5)
    assert [b.box for b in found] == [Patch(30, 20, 33, 45)]
    assert found[0].ys.min() == 20
    assert found[0].xs.max() == 33
    assert len(found[0].ys) == 4 * 26


def test_diagonal_neighbours_are_one_run() -> None:
    ink = _ink((20, 20, 23, 23), (24, 24, 27, 27))
    assert [b.box for b in _blobs(ink)] == [Patch(20, 20, 27, 27)]


def test_dust_giants_and_runs_on_the_edge_are_dropped() -> None:
    ink = _ink(
        (20, 20, 20, 21),  # two pixels: dust
        (40, 10, 41, 70),  # taller than 4 lines: a table edge
        (0, 30, 5, 40),  # touches the region's edge
        (60, 50, 63, 62),  # a glyph
    )
    assert [b.box for b in _blobs(ink)] == [Patch(60, 50, 63, 62)]


def test_a_busy_region_is_no_margin() -> None:
    ink = _ink((10, 10, 70, 100))
    assert _blobs(ink, busy=0.3) == []


def test_blobs_within_a_line_are_one_patch() -> None:
    near = [_blob(10, 10, 14, 30), _blob(22, 12, 26, 30), _blob(100, 10, 104, 30)]
    grouped = patches(near, _UNIT)
    assert [box for box, _ in grouped] == [
        Patch(10, 10, 26, 30),
        Patch(100, 10, 104, 30),
    ]
    assert [len(members) for _, members in grouped] == [2, 1]


def test_overlapping_columns_are_one_glyph_and_the_rest_keep_their_order() -> None:
    bar, stem = _blob(10, 10, 30, 12), _blob(18, 14, 22, 40)  # a 4: bar over stem
    other = _blob(40, 10, 50, 40)
    assert merge_glyphs([other, stem, bar]) == [
        Patch(10, 10, 30, 40),
        Patch(40, 10, 50, 40),
    ]
