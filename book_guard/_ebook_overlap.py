# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""How in-app sessions and paper sessions share the clock.

Nobody reads the paper copy and the app at once, so the same hour never
counts twice:

* an in-app session that overlaps a paper session that can count is
  refused when it arrives (:func:`paper_conflict`);
* a paper session formed later across an in-app session does not count
  (:func:`clashes`, ``_state.OVERLAP``);
* an in-app session closes a paper start photo taken before it
  (:func:`breaks`): the reader takes a start photo right after each stop
  photo, so the next photo is a new start, never that start's stop. So does
  a switch of books (:func:`~book_guard._books.switch_times`).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from book_guard import _ledger, _photos
from book_guard._books import all_books, book_at, switch_times
from book_guard._sessions import TOO_FAST, build_sessions

if TYPE_CHECKING:
    from collections.abc import Iterable, Sequence
    from datetime import datetime

    from book_guard._books import Book
    from book_guard._ledger import Ledger
    from book_guard._paths import Paths
    from book_guard._sessions import Session

type Span = tuple[datetime, datetime]
"""From when to when."""


def overlaps(a: Span, b: Span) -> bool:
    """Whether two spans share any moment (touching ends do not)."""
    return a[0] < b[1] and b[0] < a[1]


def session_breaks(starts: Iterable[datetime], ledger: Ledger) -> list[datetime]:
    """Moments that close an open paper start: Start taps and book switches.

    The one place the list is made, so no caller of ``build_sessions`` or
    ``open_start`` can forget one of the kinds.
    """
    return [*starts, *switch_times(ledger)]


def breaks(app: Sequence[Session], ledger: Ledger) -> list[datetime]:
    """When each in-app session started or the book was switched."""
    return session_breaks((s.start.taken for s in app), ledger)


def clashes(session: Session, app: list[Session]) -> bool:
    """A paper session during hours already read in the app."""
    return session.ebook is None and any(
        overlaps((session.start.taken, session.end.taken), (a.start.taken, a.end.taken))
        for a in app
    )


def paper_conflict(paths: Paths, span: Span, starts: list[datetime]) -> str | None:
    """Why ``span`` clashes with a paper session that can count, or None.

    ``starts`` are the stored in-app sessions' Start taps; book switches
    from the ledger are added (:func:`session_breaks`).
    A flipped-through paper session (too fast) never counts, so it is no
    clash; an open start photo is none either (see the module docstring).
    """
    pages = _photos.usable_pages(_photos.load(paths.photos))
    ledger = _ledger.load(paths.ledger, paths.key_file)
    for s in build_sessions(pages, session_breaks(starts, ledger)):
        if s.state != TOO_FAST and overlaps(span, (s.start.taken, s.end.taken)):
            return (
                f"You were reading on paper then (p. {s.start.page}-{s.end.page}):"
                " one session at a time."
            )
    return None


def book_of(ledger: Ledger, session: Session) -> Book | None:
    """The book a session read: an in-app session names its own ISBN."""
    if session.ebook is None:
        return book_at(ledger, session.end.taken)
    isbn = session.ebook.isbn
    books = [b for b in all_books(ledger) if b.isbn == isbn]
    earlier = [b for b in books if b.registered_at <= session.end.taken]
    return (earlier or books)[-1] if books else None
