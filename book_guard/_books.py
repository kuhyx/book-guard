# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Registered books. The newest ``book`` entry is the one being read."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
import json
import logging
from typing import TYPE_CHECKING, Final, NamedTuple

from book_guard import _ledger
from book_guard._ledger import BOOK, Entry

if TYPE_CHECKING:
    from book_guard._ledger import Ledger
    from book_guard._openlibrary import BookInfo
    from book_guard._paths import Paths


_logger: Final = logging.getLogger(__name__)


class Chapter(NamedTuple):
    """One table-of-contents line: where a chapter starts, and its title."""

    start: int
    title: str


@dataclass(frozen=True)
class Book:
    """A book as registered: ``pages`` is the last page that counts."""

    isbn: str
    title: str
    author: str
    pages: int | None
    registered_at: datetime
    chapters: tuple[Chapter, ...] = ()

    def chapter_at(self, page: int) -> tuple[int, Chapter] | None:
        """(1-based number, chapter) that ``page`` falls in, if any."""
        found = None
        for number, chapter in enumerate(self.chapters, 1):
            if chapter.start <= page:
                found = (number, chapter)
        return found

    @property
    def label(self) -> str:
        """``Title -- Author`` for humans."""
        return f"{self.title} -- {self.author}" if self.author else self.title


def normalise_chapters(rows: object) -> tuple[Chapter, ...]:
    """Valid ``[start, title]`` rows, sorted by start page, one per start."""
    by_start: dict[int, str] = {}
    for row in rows if isinstance(rows, list | tuple) else []:
        if not isinstance(row, list | tuple) or len(row) != len(Chapter._fields):
            continue
        start, title = row
        if isinstance(start, int) and start > 0 and str(title).strip():
            by_start[start] = str(title).strip()
    return tuple(Chapter(start, by_start[start]) for start in sorted(by_start))


def _chapters_of(raw: str) -> tuple[Chapter, ...]:
    if not raw:
        return ()
    try:
        return normalise_chapters(json.loads(raw))
    except ValueError as exc:
        _logger.warning("unreadable chapter list in the ledger (%s); ignoring it", exc)
        return ()


def _from_entry(entry: Entry) -> Book:
    pages = entry.detail.get("pages", "")
    return Book(
        isbn=entry.detail.get("isbn", ""),
        title=entry.detail.get("title", ""),
        author=entry.detail.get("author", ""),
        pages=int(pages) if pages.isdigit() else None,
        registered_at=datetime.fromisoformat(entry.created_at),
        chapters=_chapters_of(entry.detail.get("chapters", "")),
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


def register(
    paths: Paths,
    info: BookInfo,
    *,
    pages: int | None = None,
    chapters: tuple[Chapter, ...] | None = None,
) -> Book:
    """Record ``info`` as the book being read (a new registration row).

    Args:
        paths: Where the ledger lives.
        info: Metadata, typically from a lookup.
        pages: Overrides ``info.pages`` -- catalogues count front matter
            differently from the printed last page.
        chapters: The table of contents; ``None`` keeps the current book's
            when it is the same ISBN (re-registering to fix a field must not
            lose an imported contents list).

    Raises:
        ValueError: The book has no ISBN.
        OSError: The ledger could not be written.
    """
    if not info.isbn:
        msg = "a book needs an ISBN to be registered"
        raise ValueError(msg)
    now = datetime.now(tz=UTC)
    count = pages if pages is not None else info.pages
    if chapters is None:
        now_reading = current(_ledger.load(paths.ledger, paths.key_file))
        same = now_reading is not None and now_reading.isbn == info.isbn
        chapters = now_reading.chapters if same and now_reading else ()
    entry = Entry(
        entry_id=f"book:{info.isbn}:{now.isoformat()}",
        kind=BOOK,
        day=now.astimezone().date().isoformat(),
        detail={
            "isbn": info.isbn,
            "title": info.title,
            "author": info.author,
            "pages": str(count) if count else "",
            "chapters": json.dumps([list(c) for c in chapters], ensure_ascii=False)
            if chapters
            else "",
        },
        created_at=now.isoformat(),
    )
    _ledger.append(paths.ledger, paths.key_file, entry)
    return _from_entry(entry)
