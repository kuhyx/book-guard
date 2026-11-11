# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_pencil_norm: a glyph mask becomes the 28x28 picture the digit net knows."""

from __future__ import annotations

import numpy as np
import pytest

from book_guard import _pencil_norm as norm


def _bar(height: int, width: int, stroke: int) -> np.ndarray:
    """A vertical stroke ``stroke`` wide in a ``height`` x ``width`` box."""
    mask = np.zeros((height, width), dtype=bool)
    mask[:, :stroke] = True
    return mask


def test_stroke_width_is_twice_area_over_edge() -> None:
    assert norm.stroke_width(_bar(40, 3, 3)) == pytest.approx(2 * 120 / 82)
    wide = np.zeros((60, 30), dtype=bool)
    wide[:, 10:16] = True  # a 6 px stroke inside a wider box
    assert norm.stroke_width(wide) == pytest.approx(6, rel=0.1)


def test_a_mask_with_no_edge_is_as_wide_as_tall() -> None:
    assert norm.stroke_width(np.zeros((9, 4), dtype=bool)) == 9.0


def test_thicken_grows_every_side_and_zero_is_a_no_op() -> None:
    mask = np.zeros((5, 5), dtype=bool)
    mask[2, 2] = True
    assert norm.thicken(mask, 0) is mask
    grown = norm.thicken(mask, 1)
    assert grown.shape == (7, 7)
    assert grown[2:5, 2:5].all()
    assert grown.sum() == 9


def test_squeeze_is_the_ink_share_of_each_block() -> None:
    mask = np.zeros((4, 4), dtype=bool)
    mask[:2, :2] = True
    mask[0, 2] = True
    assert norm.squeeze(mask, 2, 2).tolist() == [[1.0, 0.25], [0.0, 0.0]]
    # Upscaling: every cell still has one pixel behind it.
    assert norm.squeeze(np.array([[True, False]]), 2, 4).tolist() == [
        [1.0, 1.0, 0.0, 0.0],
        [1.0, 1.0, 0.0, 0.0],
    ]


def test_recentre_moves_the_centre_of_mass_to_the_middle() -> None:
    picture = np.zeros((28, 28))
    picture[2:5, 2:5] = 1.0
    moved = norm.recentre(picture)
    ys, xs = np.nonzero(moved)
    assert (ys.min() + ys.max()) / 2 == pytest.approx(13.5, abs=0.5)
    assert (xs.min() + xs.max()) / 2 == pytest.approx(13.5, abs=0.5)
    assert moved.sum() == picture.sum()


def test_recentre_leaves_an_empty_picture_and_drops_what_leaves_the_field() -> None:
    empty = np.zeros((28, 28))
    assert norm.recentre(empty) is empty
    # Two blobs, the heavy one far down: centring pushes the light one out.
    lopsided = np.zeros((28, 28))
    lopsided[0, 0] = 1.0
    lopsided[20:28, 10:12] = 5.0
    assert norm.recentre(lopsided).sum() < lopsided.sum()


def test_normalise_fits_the_glyph_in_twenty_pixels_and_centres_it() -> None:
    picture = norm.normalise(_bar(80, 8, 8), 0.14)
    assert picture.shape == (28, 28)
    rows = np.nonzero(picture.sum(axis=1))[0]
    assert rows.max() - rows.min() + 1 == 20
    assert picture.max() == pytest.approx(1.0)


def test_a_thin_stroke_is_widened_and_a_thick_one_is_left_alone() -> None:
    thin = norm.normalise(_bar(60, 3, 3), 0.14)
    thick = norm.normalise(_bar(60, 20, 20), 0.14)
    assert (thin > 0.5).sum(axis=1).max() >= 2
    assert thick.sum() > thin.sum()
    # Already wider than the target: no growth, so the same as width 0.
    assert np.array_equal(norm.normalise(_bar(60, 20, 20), 0.0), thick)
