# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Every book ever read: its sessions, full summaries, grader replies, notes.

Built from the ledger (verdict rows carry the book, pages and times, so a
session whose photos left the cache still shows), the snapshot (sessions
not graded yet, and each session's photos) and the two unsigned side files
(full summaries, notes). Written to ``Reading/library.json`` every pass --
a separate file so ``state.json`` stays small -- and printed by
``book-guard library``.

"Finished" is all-time: a credited session's end page reached the book's
last page, whenever that was (not the month's ``Pace.finished_books``).
"""

from __future__ import annotations

from datetime import datetime
import json
import logging
from typing import TYPE_CHECKING, Any, Final

from book_guard import _ledger, _notes, _summaries
from book_guard._atomic_json import write_json
from book_guard._books import Book, all_books
from book_guard._ledger import CREDIT
from book_guard._session_files import photo_ref, session_numbers

if TYPE_CHECKING:
    from book_guard._ledger import Entry
    from book_guard._paths import Paths
    from book_guard._sessions import Session
    from book_guard._state import SessionView, Snapshot

_logger: Final = logging.getLogger(__name__)

SCHEMA: Final = 1
FINISHED: Final = "finished"
READING: Final = "reading"
UNREAD: Final = "not-started"


def _iso(epoch: str) -> str:
    return (
        datetime.fromtimestamp(int(epoch)).astimezone().isoformat()
        if epoch.isdigit()
        else ""
    )


def _int(raw: str) -> int | None:
    return int(raw) if raw.isdigit() else None


def _attempt(row: Entry, full: dict[str, str]) -> dict[str, Any]:
    d = row.detail
    return {
        "id": row.entry_id,
        "passed": row.kind == CREDIT,
        "summary": _summaries.full_text(full, row),
        "feedback": d.get("feedback", ""),
        "missing": [m for m in d.get("missing", "").split("\n") if m],
        "grader": d.get("grader", ""),
        "graded": d.get("graded", "1") != "0",
        "at": row.created_at,
    }


def _numbers(d: dict[str, str], s: Session | None) -> dict[str, Any]:
    """Pages and times: the photos' (with any narrowed times), else the row's."""
    if s is not None:
        return session_numbers(s)
    return {
        "start_page": _int(d.get("start_page", "")),
        "end_page": _int(d.get("end_page", "")),
        "pages": _int(d.get("pages", "")),
        "minutes": _int(d.get("minutes", "")),
        "started_at": _iso(d.get("started_at", "")),
        "ended_at": _iso(d.get("ended_at", "")),
    }


def _session(
    sid: str, rows: list[Entry], view: SessionView | None, full: dict[str, str]
) -> dict[str, Any]:
    """One session with every graded attempt and its photos."""
    d = rows[-1].detail if rows else {}
    s = view.session if view else None
    credited = any(r.kind == CREDIT for r in rows)
    photos = (
        []
        if s is None
        else [
            photo_ref("start", s.start),
            photo_ref("end", s.end),
            photo_ref("check", s.check),
        ]
    )
    return {
        "id": sid,
        "isbn": d.get("isbn") or (view.book.isbn if view and view.book else ""),
        **_numbers(d, s),
        "status": view.status if view else ("credited" if credited else "failed-quiz"),
        "credited": credited,
        "attempts": [_attempt(r, full) for r in rows],
        "photos": [p for p in photos if p],
    }


def _sessions(
    ledger: _ledger.Ledger, snap: Snapshot, full: dict[str, str]
) -> list[dict[str, Any]]:
    views = {v.session.session_id: v for v in snap.sessions}
    verdicts = {k: v for k, v in ledger.verdicts().items() if k.startswith("session:")}
    ids = list(verdicts) + [sid for sid in views if sid not in verdicts]
    found = [_session(sid, verdicts.get(sid, []), views.get(sid), full) for sid in ids]
    return sorted(found, key=lambda s: s["ended_at"] or "")


def _book(
    book: Book,
    first: datetime,
    sessions: list[dict[str, Any]],
    notes: list[dict[str, Any]],
    *,
    current: bool,
) -> dict[str, Any]:
    """One book: all-time status, dates and pages, sessions, notes."""
    done = [s for s in sessions if s["credited"]]
    last_page = max((s["end_page"] or 0 for s in done), default=0)
    finished_at = next(
        (
            s["ended_at"]
            for s in done
            if book.pages and (s["end_page"] or 0) >= book.pages
        ),
        None,
    )
    status = FINISHED if finished_at else READING if sessions else UNREAD
    return {
        "isbn": book.isbn,
        "title": book.title,
        "author": book.author,
        "pages": book.pages,
        "chapters": [{"start": c.start, "title": c.title} for c in book.chapters],
        "registered_at": first.isoformat(),
        "current": current,
        "status": status,
        "finished_at": finished_at,
        "pages_read": sum(s["pages"] or 0 for s in done),
        "last_page_read": last_page or None,
        "first_read_at": sessions[0]["started_at"] if sessions else None,
        "last_read_at": sessions[-1]["ended_at"] if sessions else None,
        "sessions": sessions,
        "notes": notes,
    }


def build(paths: Paths, snap: Snapshot) -> dict[str, Any]:
    """The library document: books, most recently read first."""
    ledger = _ledger.load(paths.ledger, paths.key_file)
    newest: dict[str, Book] = {}
    first: dict[str, datetime] = {}
    for book in all_books(ledger):
        newest[book.isbn] = book
        first.setdefault(book.isbn, book.registered_at)
    try:
        notes = _notes.load(paths)
    except ValueError as exc:
        _logger.warning("notes unreadable (%s); the library shows none", exc)
        notes = {}
    sessions = _sessions(ledger, snap, _summaries.load(paths))
    current = snap.book.isbn if snap.book else ""
    books = [
        _book(
            b,
            first[isbn],
            [s for s in sessions if s["isbn"] == isbn],
            _notes.of_book(notes, isbn),
            current=isbn == current,
        )
        for isbn, b in newest.items()
    ]
    current_first = [b for b in books if b["current"]]
    rest = sorted(
        (b for b in books if not b["current"]),
        key=lambda b: b["last_read_at"] or b["registered_at"],
        reverse=True,
    )
    return {"schema": SCHEMA, "books": current_first + rest}


def write_library(paths: Paths, snap: Snapshot) -> None:
    """Refresh ``Reading/library.json`` when it changed; never raises."""
    target = paths.library_file
    try:
        doc = build(paths, snap)
        if target.exists() and json.loads(target.read_text("utf-8")) == doc:
            return
        write_json(target, doc, indent=1)
    except (OSError, ValueError) as exc:
        _logger.warning("could not write %s: %s", paths.library_file, exc)
