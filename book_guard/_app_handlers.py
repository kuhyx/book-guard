# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What each app request does -- thin wrappers over the CLI's own actions."""

from __future__ import annotations

import logging
import os
from typing import TYPE_CHECKING, Any, Final

from book_guard import _ledger
from book_guard._bookindex import index_path
from book_guard._books import current, normalise_chapters, register
from book_guard._flock import exclusive
from book_guard._grading import quiz_one, register_isbn
from book_guard._http import UnavailableError
from book_guard._lookup import lookup_book
from book_guard._openlibrary import BookInfo
from book_guard._requests import Response
from book_guard._reread import box_photo
from book_guard._retime import set_times
from book_guard._state import awaiting_quiz, snapshot
from book_guard._vision import normalise_isbn

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)


def _positive_int(raw: object) -> int | None:
    if isinstance(raw, bool) or not isinstance(raw, int | str):
        return None
    text = str(raw).strip()
    return int(text) if text.isdigit() and int(text) > 0 else None


def _text(raw: object) -> str:
    return raw.strip() if isinstance(raw, str) else ""


def _register(paths: Paths, request: dict[str, Any]) -> Response:
    isbn = normalise_isbn(request.get("isbn"))
    if isbn is None:
        return Response(ok=False, message="That is not a 10- or 13-digit ISBN.")
    ok, message = register_isbn(
        paths,
        isbn,
        pages=_positive_int(request.get("pages")),
        title=_text(request.get("title")),
        author=_text(request.get("author")),
    )
    return Response(ok=ok, message=message)


def _lookup(paths: Paths, request: dict[str, Any]) -> Response:
    """What the sources know about an ISBN, for the edit form to review."""
    isbn = normalise_isbn(request.get("isbn"))
    if isbn is None:
        return Response(ok=False, message="That is not a 10- or 13-digit ISBN.")
    try:
        info = lookup_book(paths, isbn)
    except UnavailableError as exc:
        _logger.warning("lookup of %s failed: %s", isbn, exc)
        return Response(ok=False, message=f"No book source reachable ({exc})")
    if info is None:
        return Response(ok=False, message=f"No source knows ISBN {isbn}.")
    found = {"isbn": isbn, "title": info.title, "author": info.author}
    return Response(
        ok=True,
        message=f"Found: {info.title}" + (f", {info.pages} p" if info.pages else ""),
        data=found | {"pages": info.pages},
    )


def _carry_index(paths: Paths, old: str, new: str) -> None:
    """Let an attached ebook follow an ISBN edit.

    Linked, not moved: older sessions, still attributed to the old ISBN,
    keep grading against the same text.
    """
    source, target = index_path(paths, old), index_path(paths, new)
    if old != new and source.exists() and not target.exists():
        os.link(source, target)


def _chapters(raw: object) -> list[list[object]]:
    """The form's ``[{"start", "title"}]`` as ``[start, title]`` rows."""
    rows = raw if isinstance(raw, list) else []
    return [[c.get("start"), c.get("title")] for c in rows if isinstance(c, dict)]


def _edit_book(paths: Paths, request: dict[str, Any]) -> Response:
    """Rewrite the current book; a field the form did not send keeps its value."""
    raw_isbn = request.get("isbn")
    new_isbn = None if raw_isbn is None else normalise_isbn(raw_isbn)
    if raw_isbn is not None and new_isbn is None:
        return Response(ok=False, message="That is not a 10- or 13-digit ISBN.")
    raw_pages = request.get("pages")
    pages = None if raw_pages in {None, ""} else _positive_int(raw_pages)
    if raw_pages not in {None, ""} and pages is None:
        return Response(ok=False, message="The last page must be a positive number.")
    with exclusive(paths):
        book = current(_ledger.load(paths.ledger, paths.key_file))
        if book is None:
            return Response(ok=False, message="No book registered yet.")
        isbn = new_isbn or book.isbn
        title = _text(request.get("title")) if "title" in request else ""
        author = _text(request.get("author")) if "author" in request else book.author
        info = BookInfo(
            title=title or book.title,
            author=author,
            pages=book.pages if raw_pages is None else pages,
            isbn=isbn,
        )
        raw_chapters = request.get("chapters")
        chapters = (
            book.chapters
            if raw_chapters is None
            else normalise_chapters(_chapters(raw_chapters))
        )
        _carry_index(paths, book.isbn, isbn)
        edited = register(paths, info, chapters=chapters)
    return Response(ok=True, message=f"Saved: {edited.label}")


def _summary(paths: Paths, request: dict[str, Any]) -> Response:
    wanted = str(request.get("session_id", ""))
    view = next(
        (v for v in awaiting_quiz(snapshot(paths)) if v.session.session_id == wanted),
        None,
    )
    if view is None:
        return Response(
            ok=False, message="That session is not waiting for a summary any more."
        )
    verdict = quiz_one(paths, view, str(request.get("summary", "")))
    return Response(ok=True, message=verdict.feedback, passed=verdict.passed)


HANDLERS: dict[str, Callable[[Paths, dict[str, Any]], Response]] = {
    "register": _register,
    "edit_book": _edit_book,
    "lookup": _lookup,
    "summary": _summary,
    "box": box_photo,
    "session_times": set_times,
}
