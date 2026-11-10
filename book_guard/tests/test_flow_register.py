# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Registering books by ISBN (_grading.register_isbn / register_lookup)."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from book_guard import _grading
from book_guard import _lookup as _lookup_mod
from book_guard._http import UnavailableError
from book_guard._openlibrary import BookInfo
from book_guard.tests._flow_helpers import ISBN13

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths


def _lookup(result: BookInfo | None) -> Any:
    return lambda _paths, _isbn: result


# -- register_isbn ----------------------------------------------------------


def test_register_isbn_offline(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    def offline(_paths: Paths, _isbn: str) -> None:
        msg = "no book source answered"
        raise UnavailableError(msg)

    monkeypatch.setattr(_grading, "lookup_book", offline)
    assert _grading.register_isbn(bg_paths, ISBN13) == (
        False,
        "No book source reachable (no book source answered); try again later",
    )
    assert not bg_paths.ledger.exists()


def test_register_unknown_isbn_asks_for_pages(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(_grading, "lookup_book", _lookup(None))
    tail = "set the last page of your copy (app, or: book-guard pages N)"
    assert _grading.register_isbn(bg_paths, ISBN13) == (
        True,
        f"Now reading: ISBN {ISBN13}; {tail}",
    )
    named = _grading.register_isbn(bg_paths, ISBN13, title="Cesarz", author="Sher")
    assert named == (True, f"Now reading: Cesarz -- Sher; {tail}")


def test_a_named_unknown_isbn_is_remembered(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    # No catalogue knows it; the name the user gave answers later lookups.
    monkeypatch.setattr(_grading, "lookup_book", _lookup(None))
    _grading.register_isbn(bg_paths, ISBN13, title="Cesarz", author="Sher")
    monkeypatch.setattr(_lookup_mod, "FETCHERS", {})
    found = _lookup_mod.lookup_book(bg_paths, ISBN13)
    assert found == BookInfo(title="Cesarz", author="Sher", pages=None, isbn=ISBN13)


def test_an_unnamed_unknown_isbn_is_not_remembered(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(_grading, "lookup_book", _lookup(None))
    _grading.register_isbn(bg_paths, ISBN13)
    assert not bg_paths.isbn_cache.exists()


def test_register_with_pages_override(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    info = BookInfo(title="War", author="Tol", pages=900, isbn=ISBN13)
    monkeypatch.setattr(_grading, "lookup_book", _lookup(info))
    assert _grading.register_isbn(bg_paths, ISBN13) == (
        True,
        "Now reading: War -- Tol, last page 900",
    )
    _ok, message = _grading.register_isbn(bg_paths, ISBN13, pages=1225)
    assert message.endswith("page 1225")
