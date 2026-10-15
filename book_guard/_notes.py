# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The reader's free-text notes per book, written in the app.

They arrive as ``note`` requests through the app's outbox (so a note taken
offline goes up later) and live in ``data_dir/notes.json``, outside the
signed ledger: a note carries no value. The app names each note with its
own id, so sending it twice (a retried outbox item) or editing it is the
same upsert; the newer ``updated_at`` wins. Nothing is ever deleted -- an
edit keeps the text it replaced under ``previous``, and an empty edit is
refused rather than read as a delete.
"""

from __future__ import annotations

from datetime import UTC, datetime
import json
import logging
import re
from typing import TYPE_CHECKING, Any, Final

from book_guard import _ledger
from book_guard._atomic_json import write_json
from book_guard._books import all_books
from book_guard._errors import CorruptFileError
from book_guard._flock import exclusive
from book_guard._requests import Response

if TYPE_CHECKING:
    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

NOTE_ID: Final = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
MAX_NOTE_CHARS: Final = 20000
MAX_CHAPTER_CHARS: Final = 300


def load(paths: Paths) -> dict[str, dict[str, Any]]:
    """Note id -> note; missing is empty.

    Raises:
        CorruptFileError: The file exists but is not a notes file -- never
            overwrite what cannot be read.
    """
    try:
        raw = json.loads(paths.notes.read_text(encoding="utf-8"))
    except FileNotFoundError:
        _logger.warning("no notes at %s yet; starting empty", paths.notes)
        return {}
    if not isinstance(raw, dict):
        msg = f"{paths.notes} is not a notes file"
        raise CorruptFileError(msg)
    return {k: v for k, v in raw.items() if isinstance(v, dict)}


def of_book(notes: dict[str, dict[str, Any]], isbn: str) -> list[dict[str, Any]]:
    """``isbn``'s notes, by page (unpaged last), then by when written."""
    found = [n for n in notes.values() if n.get("isbn") == isbn]
    return sorted(
        found,
        key=lambda n: (
            n.get("page") is None,
            n.get("page") or 0,
            n.get("created_at", ""),
        ),
    )


def _when(raw: object) -> str:
    """An ISO time the app sent, normalised to UTC; now if absent or bad."""
    try:
        moment = datetime.fromisoformat(str(raw))
    except ValueError:
        _logger.warning("note time %r is not ISO; using now", raw)
        return datetime.now(tz=UTC).isoformat()
    return (
        (moment if moment.tzinfo else moment.replace(tzinfo=UTC))
        .astimezone(UTC)
        .isoformat()
    )


def _page(raw: object) -> int | None:
    if isinstance(raw, bool) or not isinstance(raw, int | str):
        return None
    text = str(raw).strip()
    return int(text) if text.isdigit() and int(text) > 0 else None


def _validate(paths: Paths, request: dict[str, Any]) -> str | None:
    """Why the request cannot be stored, or None."""
    if not NOTE_ID.fullmatch(str(request.get("note_id", ""))):
        return "A note needs an id of 8-64 letters, digits, - or _."
    text = request.get("text")
    if not isinstance(text, str) or not text.strip():
        return "A note cannot be empty (notes are never deleted)."
    if len(text) > MAX_NOTE_CHARS:
        return f"A note is at most {MAX_NOTE_CHARS} characters."
    isbn = str(request.get("isbn", ""))
    if isbn not in {
        b.isbn for b in all_books(_ledger.load(paths.ledger, paths.key_file))
    }:
        return f"No registered book has ISBN {isbn!r}."
    return None


def upsert(paths: Paths, request: dict[str, Any]) -> Response:
    """Store (or update) one note; the ``note`` request handler."""
    problem = _validate(paths, request)
    if problem:
        return Response(ok=False, message=problem)
    note_id = str(request["note_id"])
    updated = _when(request.get("updated_at"))
    with exclusive(paths):
        notes = load(paths)
        old = notes.get(note_id)
        if old is not None and old.get("updated_at", "") > updated:
            return Response(
                ok=True, message="A newer edit of this note is already saved."
            )
        previous = list(old.get("previous", [])) if old else []
        if old is not None and old.get("text") != request["text"].strip():
            previous.append(
                {"text": old.get("text", ""), "updated_at": old.get("updated_at", "")}
            )
        notes[note_id] = {
            "id": note_id,
            "isbn": str(request["isbn"]),
            "text": request["text"].strip(),
            "page": _page(request.get("page")),
            "chapter": str(request.get("chapter") or "").strip()[:MAX_CHAPTER_CHARS],
            "created_at": old.get("created_at", updated)
            if old
            else _when(request.get("created_at")),
            "updated_at": updated,
            "previous": previous,
        }
        write_json(paths.notes, notes, indent=1)
    return Response(ok=True, message="Note saved." if old is None else "Note updated.")
