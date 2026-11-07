# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Hermetic defaults for every test.

Autouse, so no test can forget them:

* every path (ledger, photo cache, the WebDAV Reading folder, the HMAC key)
  points into ``tmp_path`` -- the real ~/.local/share/book_guard and
  ~/data/cloud/Reading are never touched;
* the Claude CLI, the network (urllib) and desktop notifications raise or
  no-op unless a test installs its own fake;
* embeddings come from a tiny deterministic fake instead of fastembed; where
  fastembed is not installed (Python 3.15: no onnxruntime wheel yet) a fake
  ``fastembed`` module stands in for it;
* the background index unit is never started (``systemctl --user start``
  raises unless a test installs its own fake); a test that runs a repo shell
  script against stub commands on ``PATH`` asks for :func:`run_script`;
* focus projects: ``book_guard._focus.stands_down`` answers from the per-test
  :func:`focus_pool` set (empty unless a test adds a day), never the real
  registry;
* the free-day pool is empty, and the sick-day pool is the per-test
  :func:`sick_pool` dict (empty unless a test marks a day): every sickdays
  read is answered from it, so kuhy's real pool is never read.
"""

from __future__ import annotations

import hashlib
import importlib
import importlib.util
import subprocess
import sys
import types
from typing import TYPE_CHECKING, Final

import numpy as np
import pytest
import sickdays

from book_guard import _focus, _http, _openlibrary, _paths
from book_guard._paths import Paths
from scripts import check_onnxruntime_wheel

if TYPE_CHECKING:
    from collections.abc import Callable, Iterator
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


_REAL_RUN: Final = subprocess.run
"""Captured before ``_hermetic`` replaces ``subprocess.run`` for every test."""


@pytest.fixture
def run_script() -> Callable[..., subprocess.CompletedProcess[str]]:
    """The real ``subprocess.run``, for a repo script run against stubs only.

    The test must put stub executables first on ``PATH`` (and point every
    other external at a stub) so the script reaches nothing real.
    """
    return _REAL_RUN


@pytest.fixture
def focus_pool() -> set[date]:
    """This test's focus days on which the ``book`` gate stands down."""
    return set()


@pytest.fixture
def sick_pool() -> SickPool:
    """This test's sick-day pool: add ``{day: frozenset(kept lockers)}``."""
    return {}


def _fastembed(monkeypatch: pytest.MonkeyPatch) -> types.ModuleType:
    """The ``fastembed`` module ``_embed`` will import: real, or a stand-in.

    On a Python with no fastembed install (3.15) a bare module is put in
    ``sys.modules`` so the embedding code still runs and is covered there.
    """
    if importlib.util.find_spec("fastembed") is not None:
        return importlib.import_module("fastembed")
    stand_in = types.ModuleType("fastembed")
    monkeypatch.setitem(sys.modules, "fastembed", stand_in)
    return stand_in


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
    bg_paths: Paths,
    sick_pool: SickPool,
    focus_pool: set[date],
    monkeypatch: pytest.MonkeyPatch,
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
    monkeypatch.setattr(check_onnxruntime_wheel, "urlopen", no_network)  # PyPI
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
    monkeypatch.setattr(
        _fastembed(monkeypatch),
        "TextEmbedding",
        lambda *_a, **_k: FakeEmbedder(),
        raising=False,  # the 3.15 stand-in module starts empty
    )
    monkeypatch.setattr("freedays.is_free_day", lambda *_a, **_k: False)
    # The shared sick-day pool is kuhy's real file: no test may read it.
    _fake_sick_pool(monkeypatch, sick_pool)
    # The focus-project registry is kuhy's real file: answer from focus_pool.
    monkeypatch.setattr(
        _focus, "stands_down", lambda gate, day: gate == "book" and day in focus_pool
    )
    monkeypatch.setattr(_focus, "project_name", lambda _day: "Test project")
    monkeypatch.setattr("shutil.which", lambda _name: None)
    # The morning carrot reads bg_paths.morning_session (under tmp_path), and
    # a production-mode test must never wait 30 real seconds for it.
    monkeypatch.setattr("book_guard._morning.MORNING_RETRY_SECONDS", 0.0)
    yield
    _paths.set_override(None)
