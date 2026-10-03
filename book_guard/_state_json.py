# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The snapshot as JSON for the app -- written next to NEXT.txt every pass.

Schema version 1. Every field the app shows comes from here; the app never
derives pace or session state itself, so the PC stays the only authority.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any, Final

from book_guard import _photos as _photo_cache
from book_guard._bookindex import index_path
from book_guard._errlog import claude_down_since
from book_guard._render import todo_lines
from book_guard._session_files import file_name
from book_guard._thumbs import thumb_name

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._state import SessionView, Snapshot

SCHEMA: Final = 1
_GALLERY: Final = 40


def _session(view: SessionView) -> dict[str, Any]:
    s = view.session
    return {
        "id": s.session_id,
        "start_page": s.start.page,
        "end_page": s.end.page,
        "check_page": s.check_page,
        "pages": s.pages,
        "minutes": s.minutes,
        "started_at": s.started_at.isoformat(),
        "ended_at": s.ended_at.isoformat(),
        "photo_start": s.start.taken.isoformat(),
        "photo_end": s.end.taken.isoformat(),
        "status": view.status,
        "book": view.book.title if view.book else "",
        "detail": f"sessions/{file_name(s.session_id)}",
    }


def _latest_page(snap: Snapshot) -> int | None:
    """The newest photographed page of the current book: where the reader is."""
    book = snap.book
    seen = [
        (v.session.end.taken, v.session.end.page)
        for v in snap.sessions
        if book and v.book and v.book.isbn == book.isbn
    ]
    if snap.open_start is not None:
        seen.append((snap.open_start.taken, snap.open_start.page))
    pages = [(taken, page) for taken, page in seen if page]
    return max(pages)[1] if pages else None


def _chapter(snap: Snapshot) -> dict[str, Any] | None:
    page = _latest_page(snap)
    found = snap.book.chapter_at(page) if snap.book and page else None
    if found is None or snap.book is None:
        return None
    number, chapter = found
    return {"number": number, "of": len(snap.book.chapters), "title": chapter.title}


def _photos(paths: Paths) -> list[dict[str, Any]]:
    """The newest photos, for the gallery: where to fetch them, what they were."""
    records = sorted(
        _photo_cache.load(paths.photos).values(),
        key=lambda r: r.taken_at or r.uploaded_at,
        reverse=True,
    )
    return [
        {
            "name": r.name,
            "file": f"processed/{r.sha[:12]}-{r.name}",
            "thumb": f"thumbs/{thumb_name(r.sha)}",
            "kind": r.kind,
            "page": r.page,
            "status": r.status,
            "reason": r.reason,
            "taken_at": r.taken_at or r.uploaded_at,
        }
        for r in records[:_GALLERY]
    ]


def to_json(paths: Paths, snap: Snapshot) -> dict[str, Any]:
    """Everything the app renders."""
    book = snap.book
    pace = snap.pace
    start = snap.open_start
    return {
        "schema": SCHEMA,
        "generated_at": datetime.now(tz=UTC).isoformat(),
        "today": snap.today.isoformat(),
        "locked": snap.locked,
        "reason": snap.reason,
        "book": None
        if book is None
        else {
            "isbn": book.isbn,
            "title": book.title,
            "author": book.author,
            "pages": book.pages,
            "has_file": index_path(paths, book.isbn).exists(),
            "chapters": [{"start": c.start, "title": c.title} for c in book.chapters],
            "chapter": _chapter(snap),
        },
        "pace": {
            "month": pace.month.isoformat()[:7],
            "target": pace.target,
            "pages": pace.pages,
            "required": pace.required,
            "behind": pace.behind,
            "carried_debt": pace.carried_debt,
            "carried_credit": pace.carried_credit,
            "finished_books": pace.finished_books,
        },
        "open_start": None
        if start is None
        else {"page": start.page, "taken_at": start.taken.isoformat()},
        "todo": todo_lines(snap),
        "sessions": [_session(v) for v in snap.sessions],
        "escapes_left": snap.escapes_left,
        "photos": _photos(paths),
        "claude_down_since": claude_down_since(paths),
    }
