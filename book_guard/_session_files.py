# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""One detail file per session, for the app's history view.

``state.json`` lists every session in a line each; what the reader wants on
tapping one -- the photos, what was read off them, the summary they wrote
and what the grader said -- lives in ``Reading/sessions/<id>.json`` so the
snapshot stays small however long the history grows. Rewritten only when
the content changed.
"""

from __future__ import annotations

import json
import logging
import re
from typing import TYPE_CHECKING, Any, Final

from book_guard._atomic_json import write_json
from book_guard._summaries import full_text
from book_guard._summaries import load as load_summaries
from book_guard._thumbs import thumb_name

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._photos import PhotoRecord
    from book_guard._sessions import Session
    from book_guard._state import SessionView, Snapshot

_logger: Final = logging.getLogger(__name__)
_UNSAFE: Final = re.compile(r"[^A-Za-z0-9_-]")


def file_name(session_id: str) -> str:
    """``session:ab-cd`` -> ``session_ab-cd.json`` (share-safe)."""
    return f"{_UNSAFE.sub('_', session_id)}.json"


def photo_ref(role: str, record: PhotoRecord | None) -> dict[str, Any] | None:
    """Where a session photo and its thumb sit on the share; None if absent.

    Shared with the library, which lists the same photos.
    """
    if record is None or record.kind == "ebook":
        return None  # an in-app session's ends are taps, not photos
    return {
        "role": role,
        "page": record.page,
        "file": f"processed/{record.sha[:12]}-{record.name}",
        "thumb": f"thumbs/{thumb_name(record.sha)}",
    }


def session_numbers(s: Session) -> dict[str, Any]:
    """A session's pages and times as the app reads them."""
    return {
        "start_page": s.start.page,
        "end_page": s.end.page,
        "pages": s.pages,
        "minutes": s.minutes,
        "started_at": s.started_at.isoformat(),
        "ended_at": s.ended_at.isoformat(),
        "source": "ebook" if s.estimated else "photos",
        "estimated": s.estimated,
    }


def _photo(role: str, record: PhotoRecord | None) -> dict[str, Any] | None:
    ref = photo_ref(role, record)
    if ref is None or record is None:
        return None
    return {**ref, "taken_at": record.taken_at, "text": record.text}


def detail(view: SessionView, full: dict[str, str] | None = None) -> dict[str, Any]:
    """Everything the history screen shows for one session (newest verdict).

    ``full`` is the full-summary store; the summary falls back to the
    ledger's 1000-character copy.
    """
    s = view.session
    verdict = view.last_verdict
    photos = [
        _photo("start", s.start),
        _photo("end", s.end),
        _photo("check", s.check),
    ]
    found = verdict.detail if verdict else {}
    return {
        "id": s.session_id,
        "book": view.book.title if view.book else "",
        **session_numbers(s),
        "status": view.status,
        "photos": [p for p in photos if p is not None],
        "summary": full_text(full or {}, verdict) if verdict else "",
        "feedback": found.get("feedback", ""),
    }


def write_session_files(paths: Paths, snap: Snapshot) -> None:
    """Refresh ``Reading/sessions/``; failures are logged, never raised."""
    full = load_summaries(paths)
    for view in snap.sessions:
        target = paths.sessions / file_name(view.session.session_id)
        doc = detail(view, full)
        try:
            if target.exists() and json.loads(target.read_text("utf-8")) == doc:
                continue
            write_json(target, doc, indent=1)
        except (OSError, ValueError) as exc:
            _logger.warning("could not write %s: %s", target.name, exc)
