# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Embedding with fastembed: building a book's index and embedding queries.

Split from :mod:`book_guard._bookindex` so that reading an index (status,
state.json) never pays fastembed's ~0.4 s import; only the paths that embed
-- attaching a book, anchoring a session, the MCP search -- load it.
"""

from __future__ import annotations

from contextlib import closing
import hashlib
import logging
import sqlite3
from typing import TYPE_CHECKING, Final

from fastembed import TextEmbedding
import numpy as np
from numpy.typing import NDArray

from book_guard._bookindex import EMBED_BATCH, EMBED_MODEL, index_path, unit, windows

if TYPE_CHECKING:
    from collections.abc import Callable, Iterator
    from pathlib import Path

    from book_guard._paths import Paths

type Vector = NDArray[np.float32]

_logger: Final = logging.getLogger(__name__)

CHECKPOINT_CHUNKS: Final = 64
"""Chunks per committed checkpoint: ~10 s of work at the unit's CPU cap."""


def _embedder(paths: Paths) -> TextEmbedding:
    return TextEmbedding(EMBED_MODEL, cache_dir=str(paths.data_dir / "models"))


def _no_progress(_done: int, _total: int) -> None:
    """The progress callback for callers that do not show any."""


def build(
    paths: Paths,
    isbn: str,
    text: str,
    *,
    source: str,
    progress: Callable[[int, int], None] | None = None,
) -> int:
    """(Re)build the index for ``isbn`` from ``text``; returns the chunk count.

    Resumable: chunks are committed to ``<isbn>.partial`` every
    ``CHECKPOINT_CHUNKS``, so a run that is killed (timeout, reboot, OOM)
    picks up where it stopped -- as long as the text and the model are the
    same, which the partial's ``digest`` proves. Only a finished partial
    replaces the live index.

    ``progress(done, total)`` is called on start and after every checkpoint;
    the callback throttles its own writes.
    """
    spans = list(windows(text))
    report = progress or _no_progress
    target = index_path(paths, isbn)
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(".partial")
    with closing(_open_partial(partial)) as db:
        done = _resume(db, text, source)
        report(done, len(spans))
        chunks = _chunks(_embedder(paths), text, spans[done:])
        _checkpointed(db, chunks, done, len(spans), report)
    partial.replace(target)
    return len(spans)


def _open_partial(partial: Path) -> sqlite3.Connection:
    """The checkpoint db; a file sqlite cannot read is started over."""
    db = sqlite3.connect(partial)
    try:
        db.execute("PRAGMA schema_version").fetchone()
    except sqlite3.DatabaseError as exc:
        db.close()
        _logger.warning("unreadable %s (%s); starting it over", partial.name, exc)
        partial.unlink()
        db = sqlite3.connect(partial)
    return db


def _chunks(
    embedder: TextEmbedding, text: str, todo: list[tuple[int, int]]
) -> Iterator[tuple[int, int, bytes]]:
    """``(start, end, unit vector bytes)`` for every span in ``todo``."""
    vectors = embedder.embed([text[a:b] for a, b in todo], batch_size=EMBED_BATCH)
    for (a, b), vector in zip(todo, vectors, strict=True):
        yield a, b, unit([vector])[0].tobytes()


def _checkpointed(
    db: sqlite3.Connection,
    chunks: Iterator[tuple[int, int, bytes]],
    done: int,
    total: int,
    report: Callable[[int, int], None],
) -> None:
    """Write ``chunks`` into ``db``, one commit (and report) per checkpoint."""
    pending: list[tuple[int, int, bytes]] = []
    for chunk in chunks:
        pending.append(chunk)
        if len(pending) >= CHECKPOINT_CHUNKS:
            done += _commit(db, pending)
            report(done, total)
    done += _commit(db, pending)
    report(done, total)


def _digest(text: str) -> str:
    """What a partial index was built from: the text and the model."""
    return hashlib.sha256(f"{EMBED_MODEL}\n{text}".encode()).hexdigest()


def _resume(db: sqlite3.Connection, text: str, source: str) -> int:
    """Chunks already in the partial ``db`` for ``text``; resets a stale one."""
    db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
    db.execute("CREATE TABLE IF NOT EXISTS chunks (start INT, end INT, vector BLOB)")
    row = db.execute("SELECT value FROM meta WHERE key = 'digest'").fetchone()
    if row is None or row[0] != _digest(text):
        db.execute("DELETE FROM meta")
        db.execute("DELETE FROM chunks")
        db.executemany(
            "INSERT INTO meta VALUES (?, ?)",
            [
                ("text", text),
                ("source", source),
                ("model", EMBED_MODEL),
                ("digest", _digest(text)),
            ],
        )
        db.commit()
        return 0
    count: int = db.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
    return count


def _commit(db: sqlite3.Connection, pending: list[tuple[int, int, bytes]]) -> int:
    """Write ``pending`` chunks as one checkpoint; returns how many, emptied."""
    db.executemany("INSERT INTO chunks VALUES (?, ?, ?)", pending)
    db.commit()
    written = len(pending)
    pending.clear()
    return written


def embed_queries(paths: Paths, texts: list[str]) -> list[Vector]:
    """Embed free text (photo transcriptions, search queries)."""
    return [np.asarray(v, dtype=np.float32) for v in _embedder(paths).embed(texts)]
