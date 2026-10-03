# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Registering a book and grading a summary.

Shared by the CLI, the lock, the timer pass and the app's request handlers;
kept out of ``_actions`` so the handlers can import it without a cycle.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Final

from book_guard._anchor import find_span
from book_guard._books import register
from book_guard._claude import DEFAULT_MODEL
from book_guard._constants import MAX_ATTEMPTS
from book_guard._flock import exclusive
from book_guard._http import UnavailableError
from book_guard._lookup import lookup_book
from book_guard._openlibrary import BookInfo
from book_guard._publish import write_next_file
from book_guard._quiz import Verdict, grade, record_verdict
from book_guard._state import snapshot

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._state import SessionView

_logger: Final = logging.getLogger(__name__)


def register_isbn(
    paths: Paths,
    isbn: str,
    *,
    pages: int | None = None,
    title: str = "",
    author: str = "",
) -> tuple[bool, str]:
    """Look ``isbn`` up everywhere and register it: (registered, a line).

    An ISBN no source knows is still registered -- with no page count, which
    the app or ``book-guard pages N`` fills in -- so an obscure book never
    blocks reading. Such a book is named by ``title``/``author`` when the
    caller has them, else "ISBN <n>". Only when no source answered at all is
    nothing registered. The lookup runs outside the ledger lock (it can take
    a minute); only the write takes it.
    """
    try:
        info = lookup_book(paths, isbn)
    except UnavailableError as exc:
        _logger.warning("ISBN lookup for %s failed: %s", isbn, exc)
        return False, f"No book source reachable ({exc}); try again later"
    info = info or BookInfo(
        title=title or f"ISBN {isbn}", author=author, pages=None, isbn=isbn
    )
    with exclusive(paths):
        book = register(paths, info, pages=pages)
    tail = (
        f", last page {book.pages}"
        if book.pages
        else "; set the last page of your copy (app, or: book-guard pages N)"
    )
    return True, f"Now reading: {book.label}{tail}"


def quiz_one(
    paths: Paths, view: SessionView, summary: str, *, model: str = DEFAULT_MODEL
) -> Verdict:
    """Grade one summary and record the verdict. Raises if Claude is down.

    A first failure leaves one rewrite, and the feedback says so; the second
    verdict is final.
    """
    span = find_span(paths, view.book.isbn if view.book else "", view.session)
    _logger.info("grading %s: book text %s", view.session.session_id, span.reason)
    verdict = grade(view.book, view.session, summary, model=model, span=span.text)
    with exclusive(paths):
        entry = record_verdict(paths, view.book, view.session, verdict, summary)
    if entry is None:
        return Verdict(passed=False, feedback="This session was already graded.")
    write_next_file(paths, snapshot(paths))
    if verdict.passed or int(entry.detail["attempt"]) >= MAX_ATTEMPTS:
        return verdict
    return Verdict(
        passed=False,
        feedback=f"{verdict.feedback} You may rewrite this summary once; "
        "the second verdict is final.",
    )
