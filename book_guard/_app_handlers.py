# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What each app request does -- thin wrappers over the CLI's own actions."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from book_guard import _ledger
from book_guard._books import current, register
from book_guard._flock import exclusive
from book_guard._grading import quiz_one, register_isbn
from book_guard._openlibrary import BookInfo
from book_guard._requests import Response
from book_guard._state import awaiting_quiz, snapshot
from book_guard._vision import normalise_isbn

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard._paths import Paths


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


def _set_pages(paths: Paths, request: dict[str, Any]) -> Response:
    pages = _positive_int(request.get("pages"))
    if pages is None:
        return Response(ok=False, message="The last page must be a positive number.")
    with exclusive(paths):
        book = current(_ledger.load(paths.ledger, paths.key_file))
        if book is None:
            return Response(ok=False, message="No book registered yet.")
        info = BookInfo(
            title=book.title, author=book.author, pages=pages, isbn=book.isbn
        )
        register(paths, info)
    return Response(ok=True, message=f"{book.label}: last page {pages}")


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
    "set_pages": _set_pages,
    "summary": _summary,
}
