# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Hermetic defaults for every test.

Autouse, so no test can forget them:

* every path (ledger, photo cache, the WebDAV Reading folder, the HMAC key)
  points into ``tmp_path`` -- the real ~/.local/share/book_guard and
  ~/data/cloud/Reading are never touched;
* the Claude CLI, the network (urllib) and desktop notifications raise or
  no-op unless a test installs its own fake;
* embeddings come from a tiny deterministic fake instead of fastembed;
* the background index unit is never started (``systemctl --user start``
  raises unless a test installs its own fake);
* the free-day pool is empty, and the sick-day pool is the per-test
  :func:`sick_pool` dict (empty unless a test marks a day): every sickdays
  read is answered from it, so kuhy's real pool is never read.
"""

from __future__ import annotations

import hashlib
from typing import TYPE_CHECKING

import numpy as np
import pytest
import sickdays

from book_guard import _embed, _http, _openlibrary, _paths
from book_guard._paths import Paths

if TYPE_CHECKING:
    from collections.abc import Iterator
    from datetime import date
    from pathlib import Path

type SickPool = dict[date, frozenset[str]]
"""A sick day -> the lockers it keeps (``sickdays.LOCKER_*``)."""


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
        night_lockdown=tmp_path / "locked_at_epoch",
    )


@pytest.fixture
def sick_pool() -> SickPool:
    """This test's sick-day pool: add ``{day: frozenset(kept lockers)}``."""
    return {}


def _fake_sick_pool(monkeypatch: pytest.MonkeyPatch, pool: SickPool) -> None:
    """Answer every sickdays read the gate makes from ``pool``."""

    def stands_down(locker: str, day: date, **_k: object) -> bool:
        if locker not in sickdays.LOCKERS:
            msg = f"unknown locker {locker!r}"
            raise ValueError(msg)
        return day in pool and locker not in pool[day]

    monkeypatch.setattr("sickdays.sick_days", lambda **_k: frozenset(pool))
    monkeypatch.setattr("sickdays.is_sick_day", lambda day, **_k: day in pool)
    monkeypatch.setattr(
        "sickdays.kept_lockers", lambda day, **_k: pool.get(day, frozenset())
    )
    monkeypatch.setattr("sickdays.stands_down", stands_down)

    def no_pool_write(*_a: object, **_k: object) -> object:
        msg = "test tried to write the real sick-day pool: use sick_pool"
        raise AssertionError(msg)

    # book-guard never writes the pool; a test that tried would reach the
    # real file (the writers resolve their paths in sickdays' own modules).
    for writer in ("add_sick_day", "set_kept_lockers", "remove_sick_day", "sync"):
        monkeypatch.setattr(f"sickdays.{writer}", no_pool_write)


@pytest.fixture(autouse=True)
def _hermetic(
    bg_paths: Paths, sick_pool: SickPool, monkeypatch: pytest.MonkeyPatch
) -> Iterator[None]:
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
    monkeypatch.setattr("book_guard._local.urlopen", no_network)  # ollama

    def no_systemctl(*_args: object, **_kwargs: object) -> object:
        msg = "test tried to start a real systemd unit"
        raise AssertionError(msg)

    monkeypatch.setattr("book_guard._indexer.subprocess.run", no_systemctl)
    monkeypatch.delenv("BOOK_GUARD_ROOT", raising=False)
    # Lookup pacing must never really sleep in a test.
    monkeypatch.setattr("book_guard._lookup.time.sleep", lambda _s: None)
    # The fastembed CLASS is faked, not the factory, so _embed._embedder
    # itself runs (and is covered) without downloading a model.
    monkeypatch.setattr(_embed, "TextEmbedding", lambda *_a, **_k: FakeEmbedder())
    monkeypatch.setattr("freedays.is_free_day", lambda *_a, **_k: False)
    # The shared sick-day pool is kuhy's real file: no test may read it.
    _fake_sick_pool(monkeypatch, sick_pool)
    monkeypatch.setattr("shutil.which", lambda _name: None)
    # The morning carrot reads bg_paths.morning_session (under tmp_path), and
    # a production-mode test must never wait 30 real seconds for it.
    monkeypatch.setattr("book_guard._morning.MORNING_RETRY_SECONDS", 0.0)
    yield
    _paths.set_override(None)
