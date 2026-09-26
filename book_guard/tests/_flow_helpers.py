# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Builders shared by the ``test_flow_*`` modules.

Photo records, seeded sessions, registered books and ledger rows -- all
written through the package's own writers, so every test reads real files.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
import hashlib
from typing import TYPE_CHECKING, Final

from book_guard import _ledger, _photos
from book_guard._books import Book, register
from book_guard._ledger import CREDIT, ESCAPE, Entry
from book_guard._openlibrary import BookInfo
from book_guard._pace import Pace
from book_guard._photos import OK, PhotoRecord
from book_guard._sessions import build_sessions
from book_guard._state import SessionView, Snapshot

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._sessions import Session

ISBN13: Final = "9780140449136"
T0: Final = datetime(2026, 10, 5, 16, 0, tzinfo=UTC)
LOCKED_DAY: Final = date(2026, 10, 15)
"""Mid-October with no credits: 136 pages behind, so the gate locks."""
LONG_TEXT: Final = " ".join(f"word{i % 97} sentence{i % 13}." for i in range(4000))
"""Comfortably over MIN_BOOK_CHARS once normalised."""


def sha(name: str) -> str:
    """A stable 64-hex content hash for a named fake photo."""
    return hashlib.sha256(name.encode()).hexdigest()


def rec(
    name: str,
    page: int | None,
    taken: datetime,
    *,
    text: str = "",
    kind: str = "page",
    status: str = OK,
    isbn: str | None = None,
) -> PhotoRecord:
    """One cached photo record."""
    return PhotoRecord(
        sha=sha(name),
        name=f"{name}.jpg",
        taken_at=taken.isoformat(),
        uploaded_at=taken.isoformat(),
        kind=kind,
        page=page,
        isbn=isbn,
        text=text,
        status=status,
    )


def seed_photos(paths: Paths, *records: PhotoRecord) -> None:
    """Write ``records`` as the photo cache (replacing it)."""
    _photos.save(paths.photos, {r.sha: r for r in records})


def quiz_pair(
    tag: str = "q", start: datetime = T0, *, text: str = ""
) -> list[PhotoRecord]:
    """Pages 10 -> 11 five minutes apart: no check page, so NEEDS_QUIZ."""
    return [
        rec(f"{tag}-start", 10, start, text=text),
        rec(f"{tag}-end", 11, start + timedelta(minutes=5), text=text),
    ]


def check_pair(tag: str = "c", start: datetime = T0) -> list[PhotoRecord]:
    """Pages 10 -> 20 twenty minutes apart: waits for its check photo."""
    return [
        rec(f"{tag}-start", 10, start),
        rec(f"{tag}-end", 20, start + timedelta(minutes=20)),
    ]


def fast_pair(tag: str = "f", start: datetime = T0) -> list[PhotoRecord]:
    """Ten pages in one minute: TOO_FAST."""
    return [
        rec(f"{tag}-start", 10, start),
        rec(f"{tag}-end", 20, start + timedelta(minutes=1)),
    ]


def only_session(records: list[PhotoRecord]) -> Session:
    """The single session ``records`` form."""
    (session,) = build_sessions(records)
    return session


def add_book(
    paths: Paths, *, isbn: str = ISBN13, pages: int | None = 300, author: str = "Tol"
) -> Book:
    """Register a book through the real writer."""
    return register(paths, BookInfo(title="War", author=author, pages=pages, isbn=isbn))


def add_entry(
    paths: Paths, entry_id: str, kind: str, day: str, amount: int = 0
) -> None:
    """Append one signed ledger row."""
    _ledger.append(paths.ledger, paths.key_file, Entry(entry_id, kind, day, amount))


def add_credit(paths: Paths, day: str, amount: int) -> None:
    """A credited session worth ``amount`` pages on ``day``."""
    add_entry(paths, f"credit:{day}:{amount}", CREDIT, day, amount)


def add_escape(paths: Paths, day: str) -> None:
    """An escape spent on ``day``."""
    add_entry(paths, f"escape:{day}", ESCAPE, day)


def make_pace(*, required: int = 0, pages: int = 0) -> Pace:
    """A hand-built pace for rendering tests."""
    return Pace(
        month=date(2026, 10, 1),
        target=300,
        carried_debt=5,
        pages=pages,
        required=required,
        finished_books=1,
    )


def make_snap(
    *,
    book: Book | None = None,
    sessions: list[SessionView] | None = None,
    open_start: PhotoRecord | None = None,
    locked: bool = False,
) -> Snapshot:
    """A hand-built snapshot for rendering tests."""
    return Snapshot(
        today=date(2026, 10, 5),
        book=book,
        sessions=sessions or [],
        open_start=open_start,
        pace=make_pace(required=40, pages=12),
        free_today=False,
        escaped_today=False,
        escapes_left=2,
        locked=locked,
        reason="12 pages behind" if locked else "on pace",
    )


def make_book(pages: int | None = 300, author: str = "Tol") -> Book:
    """A Book value without touching the ledger."""
    return Book(isbn=ISBN13, title="War", author=author, pages=pages, registered_at=T0)
