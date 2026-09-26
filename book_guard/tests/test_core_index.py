# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_bookindex and _embed: windows, unit vectors, build/load/search."""

from __future__ import annotations

from typing import TYPE_CHECKING

import numpy as np
import pytest

from book_guard import _bookindex, _embed
from book_guard._bookindex import CHUNK_CHARS, STRIDE_CHARS, BookIndex

if TYPE_CHECKING:
    from book_guard._paths import Paths


def test_index_path(bg_paths: Paths) -> None:
    assert _bookindex.index_path(bg_paths, "978") == (
        bg_paths.data_dir / "books" / "978.sqlite"
    )


def test_windows_empty_and_short() -> None:
    assert list(_bookindex.windows("")) == []
    assert list(_bookindex.windows("abc")) == [(0, 3)]
    assert list(_bookindex.windows("x" * CHUNK_CHARS)) == [(0, CHUNK_CHARS)]


def test_windows_overlap_and_cover() -> None:
    text = "x" * 1500
    spans = list(_bookindex.windows(text))
    assert spans[0] == (0, CHUNK_CHARS)
    assert spans[1][0] == STRIDE_CHARS
    assert spans[-1][1] == len(text)
    assert all(b - a <= CHUNK_CHARS for a, b in spans)


def test_unit_scales_rows_and_survives_zero() -> None:
    matrix = _bookindex.unit([np.array([3.0, 4.0]), np.zeros(2)])
    assert matrix.dtype == np.float32
    assert np.allclose(matrix[0], [0.6, 0.8])
    assert np.allclose(matrix[1], [0.0, 0.0])


def test_book_index_search_orders_by_score() -> None:
    index = BookIndex(
        text="abcdef",
        source="s",
        offsets=[(0, 2), (2, 4), (4, 6)],
        vectors=_bookindex.unit(
            [np.array([1.0, 0.0]), np.array([0.0, 1.0]), np.array([1.0, 1.0])]
        ),
    )
    results = index.search([np.array([1.0, 0.0]), np.array([0.0, 2.0])], top=2)
    assert [h.start for h in results[0]] == [0, 4]
    assert (results[0][0].start, results[0][0].end) == (0, 2)
    assert results[0][0].score == pytest.approx(1.0)
    assert [h.start for h in results[1]] == [2, 4]
    assert len(index.search([np.array([1.0, 0.0])])[0]) == 1


def test_load_missing(bg_paths: Paths) -> None:
    assert _bookindex.load(bg_paths, "nothing") is None


def test_build_and_load_roundtrip(bg_paths: Paths) -> None:
    text = " ".join(f"word{i}" for i in range(400))
    count = _embed.build(bg_paths, "978", text, source="book.epub")
    assert count == len(list(_bookindex.windows(text)))
    index = _bookindex.load(bg_paths, "978")
    assert index is not None
    assert index.text == text
    assert index.source == "book.epub"
    assert index.offsets == list(_bookindex.windows(text))
    assert index.vectors.shape == (count, 64)
    assert np.allclose(np.linalg.norm(index.vectors, axis=1), 1.0)
    # A chunk's own text finds itself first.
    a, b = index.offsets[2]
    query = _embed.embed_queries(bg_paths, [text[a:b]])
    assert index.search(query)[0][0].start == a


def test_rebuild_replaces_and_clears_partial(bg_paths: Paths) -> None:
    _embed.build(bg_paths, "1", "first text " * 100, source="a")
    target = _bookindex.index_path(bg_paths, "1")
    target.with_suffix(".partial").write_bytes(b"leftover")
    assert _embed.build(bg_paths, "1", "second", source="b") == 1
    index = _bookindex.load(bg_paths, "1")
    assert index is not None
    assert (index.text, index.source) == ("second", "b")
    assert not target.with_suffix(".partial").exists()


def test_embed_queries(bg_paths: Paths) -> None:
    vectors = _embed.embed_queries(bg_paths, ["one two", "one two", "three"])
    assert all(v.dtype == np.float32 for v in vectors)
    assert np.array_equal(vectors[0], vectors[1])
    assert not np.array_equal(vectors[0], vectors[2])


def test_real_embedder_factory(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    # conftest fakes fastembed's class; this test swaps in a recording fake
    # to check what the factory passes it. Every other guard stays active.
    created: list[tuple[str, str]] = []

    class FakeTextEmbedding:
        def __init__(self, model: str, *, cache_dir: str) -> None:
            created.append((model, cache_dir))

    monkeypatch.setattr(_embed, "TextEmbedding", FakeTextEmbedding)
    embedder = _embed._embedder(bg_paths)
    assert isinstance(embedder, FakeTextEmbedding)
    assert created == [(_bookindex.EMBED_MODEL, str(bg_paths.data_dir / "models"))]
