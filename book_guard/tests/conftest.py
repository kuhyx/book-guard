# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Hermetic defaults for every test.

Autouse, so no test can forget them:

* every path (ledger, photo cache, the WebDAV Reading folder, the HMAC key)
  points into ``tmp_path`` -- the real ~/.local/share/book_guard and
  ~/data/cloud/Reading are never touched;
* the Claude CLI, the network (urllib) and desktop notifications raise or
  no-op unless a test installs its own fake;
* embeddings come from a tiny deterministic fake instead of fastembed;
* the free-day pool is empty.
"""

from __future__ import annotations

import hashlib
from typing import TYPE_CHECKING

import numpy as np
import pytest

from book_guard import _embed, _http, _openlibrary, _paths
from book_guard._paths import Paths

if TYPE_CHECKING:
    from collections.abc import Iterator
    from pathlib import Path


class FakeEmbedder:
    """Bag-of-words hashing into 64 dims: same words -> same direction."""

    dims = 64

    def embed(self, texts: list[str], batch_size: int = 0) -> Iterator[np.ndarray]:
        del batch_size
        for text in texts:
            vec = np.zeros(self.dims, dtype=np.float32)
            for word in text.lower().split():
                digest = hashlib.sha256(word.encode()).digest()
                vec[digest[0] % self.dims] += 1.0
            yield vec


@pytest.fixture
def bg_paths(tmp_path: Path) -> Paths:
    """The active book-guard paths for this test, all under ``tmp_path``."""
    key = tmp_path / "hmac.key"
    key.write_bytes(b"k" * 32)
    return Paths(
        data_dir=tmp_path / "data",
        reading_dir=tmp_path / "Reading",
        key_file=key,
        morning_session=tmp_path / "morning_session.json",
    )


@pytest.fixture(autouse=True)
def _hermetic(bg_paths: Paths, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    _paths.set_override(bg_paths)

    def no_claude(*_args: object, **_kwargs: object) -> object:
        msg = "test tried to run the real claude CLI"
        raise AssertionError(msg)

    def no_network(*_args: object, **_kwargs: object) -> object:
        msg = "test tried to reach the network"
        raise AssertionError(msg)

    monkeypatch.setattr("book_guard._claude.subprocess.run", no_claude)
    monkeypatch.setattr(_openlibrary, "urlopen", no_network)
    monkeypatch.setattr(_http, "urlopen", no_network)
    # Lookup pacing must never really sleep in a test.
    monkeypatch.setattr("book_guard._lookup.time.sleep", lambda _s: None)
    # The fastembed CLASS is faked, not the factory, so _embed._embedder
    # itself runs (and is covered) without downloading a model.
    monkeypatch.setattr(_embed, "TextEmbedding", lambda *_a, **_k: FakeEmbedder())
    monkeypatch.setattr("freedays.is_free_day", lambda *_a, **_k: False)
    monkeypatch.setattr("shutil.which", lambda _name: None)
    # The morning carrot reads bg_paths.morning_session (under tmp_path), and
    # a production-mode test must never wait 30 real seconds for it.
    monkeypatch.setattr("book_guard._morning.MORNING_RETRY_SECONDS", 0.0)
    yield
    _paths.set_override(None)
