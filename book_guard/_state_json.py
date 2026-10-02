# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The snapshot as JSON for the app -- written next to NEXT.txt every pass.

Schema version 1. Every field the app shows comes from here; the app never
derives pace or session state itself, so the PC stays the only authority.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any, Final

from book_guard._bookindex import index_path
from book_guard._render import todo_lines

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._state import SessionView, Snapshot

SCHEMA: Final = 1
_RECENT: Final = 20


def _session(view: SessionView) -> dict[str, Any]:
    s = view.session
    return {
        "id": s.session_id,
        "start_page": s.start.page,
        "end_page": s.end.page,
        "check_page": s.check_page,
        "pages": s.pages,
        "minutes": s.minutes,
        "started_at": s.start.taken.isoformat(),
        "status": view.status,
        "book": view.book.title if view.book else "",
    }


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
        "sessions": [_session(v) for v in snap.sessions[-_RECENT:]],
        "escapes_left": snap.escapes_left,
    }
