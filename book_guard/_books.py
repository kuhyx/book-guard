# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Registered books. The newest ``book`` entry is the one being read."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from book_guard import _ledger
from book_guard._ledger import BOOK, Entry

if TYPE_CHECKING:
    from book_guard._ledger import Ledger
    from book_guard._openlibrary import BookInfo
    from book_guard._paths import Paths


@dataclass(frozen=True)
class Book:
    """A book as registered: ``pages`` is the last page that counts."""

    isbn: str
    title: str
    author: str
    pages: int | None
    registered_at: datetime

    @property
    def label(self) -> str:
        """``Title -- Author`` for humans."""
        return f"{self.title} -- {self.author}" if self.author else self.title


def _from_entry(entry: Entry) -> Book:
    pages = entry.detail.get("pages", "")
    return Book(
        isbn=entry.detail.get("isbn", ""),
        title=entry.detail.get("title", ""),
        author=entry.detail.get("author", ""),
        pages=int(pages) if pages.isdigit() else None,
        registered_at=datetime.fromisoformat(entry.created_at),
    )


def all_books(ledger: Ledger) -> list[Book]:
    """Every registration, oldest first.

    Re-registering an ISBN (e.g. to fix the page count) appends; the newer row
    wins in :func:`book_at`.
    """
    return [_from_entry(e) for e in ledger.of_kind(BOOK)]


def book_at(ledger: Ledger, moment: datetime) -> Book | None:
    """The book being read at ``moment``: the newest registered by then.

    A photo taken before any registration is attributed to the first book,
    so photographing the pages before the barcode still counts.
    """
    books = all_books(ledger)
    earlier = [b for b in books if b.registered_at <= moment]
    if earlier:
        return earlier[-1]
    return books[0] if books else None


def current(ledger: Ledger) -> Book | None:
    """The book being read now."""
    return book_at(ledger, datetime.now(tz=UTC))


def register(paths: Paths, info: BookInfo, *, pages: int | None = None) -> Book:
    """Record ``info`` as the book being read (a new registration row).

    Args:
        paths: Where the ledger lives.
        info: Metadata, typically from Open Library.
        pages: Overrides ``info.pages`` -- Open Library counts front matter
            differently from the printed last page.

    Raises:
        ValueError: The book has no ISBN.
        OSError: The ledger could not be written.
    """
    if not info.isbn:
        msg = "a book needs an ISBN to be registered"
        raise ValueError(msg)
    now = datetime.now(tz=UTC)
    count = pages if pages is not None else info.pages
    entry = Entry(
        entry_id=f"book:{info.isbn}:{now.isoformat()}",
        kind=BOOK,
        day=now.astimezone().date().isoformat(),
        detail={
            "isbn": info.isbn,
            "title": info.title,
            "author": info.author,
            "pages": str(count) if count else "",
        },
        created_at=now.isoformat(),
    )
    _ledger.append(paths.ledger, paths.key_file, entry)
    return _from_entry(entry)
