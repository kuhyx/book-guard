# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from book_guard import _paths

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths


def test_override_is_active(bg_paths: Paths) -> None:
    assert _paths.paths() == bg_paths
    assert bg_paths.ledger.parent == bg_paths.data_dir


def test_default_and_sandbox(monkeypatch: pytest.MonkeyPatch) -> None:
    _paths.set_override(None)
    monkeypatch.delenv("BOOK_GUARD_ROOT", raising=False)
    real = _paths.paths()
    assert real.reading_dir == Path.home() / "data/cloud/Reading"
    monkeypatch.setenv("BOOK_GUARD_ROOT", "/sandbox")
    sandbox = _paths.paths()
    assert sandbox.data_dir == Path("/sandbox/data")
    assert sandbox.inbox == Path("/sandbox/Reading/inbox")
    assert sandbox.requests.name == "requests"
    assert sandbox.responses.name == "responses"
    assert sandbox.books.name == "books"
    assert sandbox.state_file.name == "state.json"
    assert sandbox.next_file.name == "NEXT.txt"
    assert sandbox.processed.name == "processed"
    assert sandbox.photos.name == "photos.json"
