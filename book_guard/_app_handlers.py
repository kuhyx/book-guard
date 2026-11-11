# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What each app request does -- thin wrappers over the CLI's own actions."""

from __future__ import annotations

from datetime import datetime
import logging
import os
from typing import TYPE_CHECKING, Any, Final

from book_guard import _ledger
from book_guard._attach import requeue
from book_guard._bookindex import index_path
from book_guard._books import current, normalise_chapters, register
from book_guard._booktext import BookTextError
from book_guard._ebook_sessions import record as record_ebook_session
from book_guard._flock import exclusive
from book_guard._grading import (
    ALREADY_CREDITED,
    quiz_one,
    register_lookup,
    switch_book,
)
from book_guard._http import UnavailableError
from book_guard._lookup import lookup_book
from book_guard._notes import upsert as upsert_note
from book_guard._openlibrary import BookInfo
from book_guard._requests import Response
from book_guard._reread import box_photo, type_page
from book_guard._retime import set_times
from book_guard._state import awaiting_quiz, snapshot
from book_guard._vision import normalise_isbn

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard._paths import Paths
    from book_guard._quiz import Verdict

_logger: Final = logging.getLogger(__name__)


def _positive_int(raw: object) -> int | None:
    if isinstance(raw, bool) or not isinstance(raw, int | str):
        return None
    text = str(raw).strip()
    return int(text) if text.isdigit() and int(text) > 0 else None


def _text(raw: object) -> str:
    return raw.strip() if isinstance(raw, str) else ""


_BAD_ISBN: Final = Response(ok=False, code="bad_isbn")


def _register(paths: Paths, request: dict[str, Any]) -> Response:
    isbn = normalise_isbn(request.get("isbn"))
    if isbn is None:
        return _BAD_ISBN
    ok, message, known = register_lookup(
        paths,
        isbn,
        pages=_positive_int(request.get("pages")),
        title=_text(request.get("title")),
        author=_text(request.get("author")),
    )
    _logger.info("register %s: %s", isbn, message)
    return Response(
        ok=ok,
        code="registered" if ok else "offline",
        data={"known": known} if ok else None,
    )


def _switch_book(paths: Paths, request: dict[str, Any]) -> Response:
    """Read a registered book from the app's tap time (``at``, with offset)."""
    isbn = normalise_isbn(request.get("isbn"))
    if isbn is None:
        return _BAD_ISBN
    raw = request.get("at")
    at = None
    if raw is not None:
        try:
            at = datetime.fromisoformat(str(raw))
        except ValueError as exc:
            _logger.warning("switch_book: unreadable time %r (%s)", raw, exc)
        if at is None or at.tzinfo is None:
            return Response(ok=False, code="bad_time")
    ok, message = switch_book(paths, isbn, at)
    _logger.info("switch to %s: %s", isbn, message)
    return Response(ok=ok, code="switched" if ok else "unknown_book")


def _lookup(paths: Paths, request: dict[str, Any]) -> Response:
    """What the sources know about an ISBN, for the edit form to review."""
    isbn = normalise_isbn(request.get("isbn"))
    if isbn is None:
        return _BAD_ISBN
    try:
        info = lookup_book(paths, isbn)
    except UnavailableError as exc:
        _logger.warning("lookup of %s failed: %s", isbn, exc)
        return Response(ok=False, code="offline")
    if info is None:
        return Response(ok=False, code="unknown_isbn")
    found = {"isbn": isbn, "title": info.title, "author": info.author}
    return Response(
        ok=True,
        code="found",
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
        return _BAD_ISBN
    raw_pages = request.get("pages")
    pages = None if raw_pages in {None, ""} else _positive_int(raw_pages)
    if raw_pages not in {None, ""} and pages is None:
        return Response(ok=False, code="bad_pages")
    with exclusive(paths):
        book = current(_ledger.load(paths.ledger, paths.key_file))
        if book is None:
            return Response(ok=False, code="no_book")
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
    _logger.info("edited: %s", edited.label)
    return Response(ok=True, code="saved", data={"pages": edited.pages})


def _verdict_code(verdict: Verdict) -> str:
    if verdict.passed:
        return "ungraded" if verdict.ungraded else "passed"
    return "already_credited" if verdict.feedback == ALREADY_CREDITED else "failed"


def _summary(paths: Paths, request: dict[str, Any]) -> Response:
    """Grade a summary: pass/fail, and on a fail the topics it must add.

    The topics are the book's own terms (content); the sentence around them
    (``feedback``) goes to the log only.
    """
    wanted = str(request.get("session_id", ""))
    view = next(
        (v for v in awaiting_quiz(snapshot(paths)) if v.session.session_id == wanted),
        None,
    )
    if view is None:
        return Response(ok=False, code="not_waiting")
    verdict = quiz_one(paths, view, str(request.get("summary", "")))
    _logger.info("summary %s: %s", wanted, verdict.feedback)
    return Response(
        ok=True,
        code=_verdict_code(verdict),
        passed=verdict.passed,
        data={"missing": list(verdict.missing)} if verdict.missing else None,
    )


def _retry_book(paths: Paths, request: dict[str, Any]) -> Response:
    """Queue a failed book file again (``books/failed/`` back to ``books/``)."""
    try:
        message = requeue(paths, _text(request.get("file")))
    except BookTextError as exc:
        _logger.warning("retry of %r refused: %s", request.get("file"), exc)
        return Response(ok=False, code="bad_file")
    _logger.info("%s", message)
    return Response(ok=True, code="requeued")


HANDLERS: dict[str, Callable[[Paths, dict[str, Any]], Response]] = {
    "register": _register,
    "switch_book": _switch_book,
    "edit_book": _edit_book,
    "lookup": _lookup,
    "summary": _summary,
    "box": box_photo,
    "type_page": type_page,
    "session_times": set_times,
    "retry_book": _retry_book,
    "note": upsert_note,
    "ebook_session": record_ebook_session,
}
