# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Embedding with fastembed: building a book's index and embedding queries.

Split from :mod:`book_guard._bookindex` so that reading an index (status,
state.json) never pays fastembed's ~0.4 s import; only the paths that embed
-- attaching a book, anchoring a session, the MCP search -- load it.
"""

from __future__ import annotations

from contextlib import closing
import sqlite3
from typing import TYPE_CHECKING

from fastembed import TextEmbedding
import numpy as np
from numpy.typing import NDArray

from book_guard._bookindex import EMBED_BATCH, EMBED_MODEL, index_path, unit, windows

if TYPE_CHECKING:
    from book_guard._paths import Paths

type Vector = NDArray[np.float32]


def _embedder(paths: Paths) -> TextEmbedding:
    return TextEmbedding(EMBED_MODEL, cache_dir=str(paths.data_dir / "models"))


def build(paths: Paths, isbn: str, text: str, *, source: str) -> int:
    """(Re)build the index for ``isbn`` from ``text``; returns the chunk count."""
    spans = list(windows(text))
    vectors = unit(
        _embedder(paths).embed([text[a:b] for a, b in spans], batch_size=EMBED_BATCH)
    )
    target = index_path(paths, isbn)
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(".partial")
    partial.unlink(missing_ok=True)
    with closing(sqlite3.connect(partial)) as db:
        db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
        db.execute("CREATE TABLE chunks (start INT, end INT, vector BLOB)")
        db.executemany(
            "INSERT INTO meta VALUES (?, ?)",
            [("text", text), ("source", source), ("model", EMBED_MODEL)],
        )
        db.executemany(
            "INSERT INTO chunks VALUES (?, ?, ?)",
            [(a, b, v.tobytes()) for (a, b), v in zip(spans, vectors, strict=True)],
        )
        db.commit()
    partial.replace(target)
    return len(spans)


def embed_queries(paths: Paths, texts: list[str]) -> list[Vector]:
    """Embed free text (photo transcriptions, search queries)."""
    return [np.asarray(v, dtype=np.float32) for v in _embedder(paths).embed(texts)]
