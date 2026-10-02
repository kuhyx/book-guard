# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The edit form's two requests: ``lookup`` and ``edit_book``."""

from __future__ import annotations

from typing import TYPE_CHECKING

from book_guard import _app_handlers, _ledger
from book_guard._app_handlers import HANDLERS
from book_guard._bookindex import index_path
from book_guard._books import Chapter, current
from book_guard._http import UnavailableError
from book_guard._openlibrary import BookInfo
from book_guard._requests import Response
from book_guard.tests._flow_helpers import ISBN13, add_book

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths


def test_edit_book_validates_and_needs_a_book(bg_paths: Paths) -> None:
    edit = HANDLERS["edit_book"]
    assert edit(bg_paths, {"pages": -3}) == Response(
        ok=False, message="The last page must be a positive number."
    )
    assert edit(bg_paths, {"isbn": "12"}) == Response(
        ok=False, message="That is not a 10- or 13-digit ISBN."
    )
    assert edit(bg_paths, {"pages": 5}) == Response(
        ok=False, message="No book registered yet."
    )


def test_edit_book_keeps_what_the_form_did_not_send(bg_paths: Paths) -> None:
    add_book(bg_paths, pages=None)
    edit = HANDLERS["edit_book"]
    assert edit(bg_paths, {"pages": 412}) == Response(
        ok=True, message="Saved: War -- Tol"
    )
    chapters = [
        {"start": 30, "title": "Two"},
        {"start": 1, "title": " One "},
        {"start": "x", "title": "bad"},
        "junk",
    ]
    edit(bg_paths, {"chapters": chapters, "title": "", "author": "Lev"})
    book = current(_ledger.load(bg_paths.ledger, bg_paths.key_file))
    assert book is not None
    assert (book.title, book.author, book.pages) == ("War", "Lev", 412)
    assert book.chapters == (Chapter(1, "One"), Chapter(30, "Two"))
    edit(bg_paths, {"pages": "", "chapters": "nope"})
    book = current(_ledger.load(bg_paths.ledger, bg_paths.key_file))
    assert book is not None
    assert (book.pages, book.chapters) == (None, ())


def test_edit_book_isbn_carries_the_ebook(bg_paths: Paths) -> None:
    add_book(bg_paths)
    old = index_path(bg_paths, ISBN13)
    old.parent.mkdir(parents=True)
    old.write_text("index", encoding="utf-8")
    new_isbn = "9788368380002"
    response = HANDLERS["edit_book"](bg_paths, {"isbn": "978-83-6838-000-2"})
    assert response.ok
    assert index_path(bg_paths, new_isbn).read_text(encoding="utf-8") == "index"
    assert old.exists()
    # Editing again with the index already there leaves it alone.
    HANDLERS["edit_book"](bg_paths, {"isbn": ISBN13})
    assert old.read_text(encoding="utf-8") == "index"


def test_lookup_answers_with_fields(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    lookup = HANDLERS["lookup"]
    assert lookup(bg_paths, {"isbn": "1"}).message.startswith("That is not")
    found = BookInfo(title="War", author="Tol", pages=900, isbn=ISBN13)
    monkeypatch.setattr(_app_handlers, "lookup_book", lambda _p, _i: found)
    assert lookup(bg_paths, {"isbn": ISBN13}) == Response(
        ok=True,
        message="Found: War, 900 p",
        data={"isbn": ISBN13, "title": "War", "author": "Tol", "pages": 900},
    )
    bare = BookInfo(title="War", author="", pages=None, isbn=ISBN13)
    monkeypatch.setattr(_app_handlers, "lookup_book", lambda _p, _i: bare)
    assert lookup(bg_paths, {"isbn": ISBN13}).message == "Found: War"
    monkeypatch.setattr(_app_handlers, "lookup_book", lambda _p, _i: None)
    assert lookup(bg_paths, {"isbn": ISBN13}) == Response(
        ok=False, message=f"No source knows ISBN {ISBN13}."
    )

    def offline(_p: Paths, _i: str) -> None:
        msg = "down"
        raise UnavailableError(msg)

    monkeypatch.setattr(_app_handlers, "lookup_book", offline)
    assert lookup(bg_paths, {"isbn": ISBN13}).message == (
        "No book source reachable (down)"
    )
