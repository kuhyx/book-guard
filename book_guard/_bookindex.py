# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A per-book search index: overlapping chunks + multilingual embeddings.

One SQLite file per ISBN under ``data_dir/books``. The full text is stored
too, so a matched region can be sliced back out by character offset -- the
grader reads the book's *continuous* text between two anchors, not a handful
of retrieved snippets.

The embedding model is multilingual on purpose: the photographed pages may
be a Polish translation of the English file (or vice versa), and a paraphrase
model maps both into the same space. Model files are cached under the data
dir, never fastembed's default in /tmp, which a reboot wipes.
"""

from __future__ import annotations

from contextlib import closing
from dataclasses import dataclass
import sqlite3
from typing import TYPE_CHECKING, Final

import numpy as np
from numpy.typing import NDArray

if TYPE_CHECKING:
    from collections.abc import Iterable, Iterator
    from pathlib import Path

    from book_guard._paths import Paths

type Matrix = NDArray[np.float32]
"""Row-per-passage unit vectors."""

EMBED_MODEL: Final = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
CHUNK_CHARS: Final = 700
EMBED_BATCH: Final = 16
"""fastembed's default batch holds hundreds of passages in memory at once:
mpnet on page-sized chunks peaked at 7.6 GiB and was OOM-killed. Small
batches keep indexing inside the inbox service's 4 GiB cap."""
STRIDE_CHARS: Final = 350
"""Half-overlapping, sub-page windows. Page-sized (1500/500) was tried on
2026-09-26 and lost: one English anchor jumped 200k characters away.
Multilingual MiniLM beat mpnet (2 misses in 10 Polish pages vs 1, and 4x
slower), so MiniLM stays; _anchor picks the best *consistent* combination of
top candidates rather than trusting any single top-1."""


@dataclass(frozen=True)
class Hit:
    """One matching chunk: where it sits in the book and how well it matched."""

    start: int
    end: int
    score: float


def index_path(paths: Paths, isbn: str) -> Path:
    """Where the index for ``isbn`` lives."""
    return paths.data_dir / "books" / f"{isbn}.sqlite"


def windows(text: str) -> Iterator[tuple[int, int]]:
    """``(start, end)`` offsets of the overlapping chunks covering ``text``."""
    start = 0
    while start < len(text):
        end = min(len(text), start + CHUNK_CHARS)
        yield start, end
        if end == len(text):
            return
        start += STRIDE_CHARS


def unit(vectors: Iterable[NDArray[np.generic]]) -> Matrix:
    """Stack ``vectors`` as float32 rows scaled to length 1 (cosine = dot)."""
    matrix: Matrix = np.asarray(list(vectors), dtype=np.float32)
    norms = np.linalg.norm(matrix, axis=1, keepdims=True)
    scaled: Matrix = (matrix / np.maximum(norms, 1e-9)).astype(np.float32)
    return scaled


@dataclass
class BookIndex:
    """A loaded index: the text, chunk offsets and unit vectors."""

    text: str
    source: str
    offsets: list[tuple[int, int]]
    vectors: Matrix

    def search(
        self, query_vectors: Iterable[NDArray[np.generic]], *, top: int = 1
    ) -> list[list[Hit]]:
        """Best chunks per query vector, by cosine similarity."""
        scores = unit(query_vectors) @ self.vectors.T
        results = []
        for row in scores:
            best = np.argsort(-row)[:top]
            results.append(
                [Hit(*self.offsets[int(i)], score=float(row[i])) for i in best]
            )
        return results


def load(paths: Paths, isbn: str) -> BookIndex | None:
    """The index for ``isbn``, or ``None`` if no book file was attached."""
    target = index_path(paths, isbn)
    if not target.exists():
        return None
    # closing(): `with connect()` only commits -- it never closes, and the
    # inbox worker is long-lived enough to leak descriptors.
    with closing(sqlite3.connect(target)) as db:
        meta = dict(db.execute("SELECT key, value FROM meta").fetchall())
        rows = db.execute(
            "SELECT start, end, vector FROM chunks ORDER BY start"
        ).fetchall()
    return BookIndex(
        text=meta["text"],
        source=meta.get("source", ""),
        offsets=[(a, b) for a, b, _ in rows],
        vectors=np.vstack([np.frombuffer(v, dtype=np.float32) for _, _, v in rows]),
    )
