# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Registering a book and grading a summary.

Shared by the CLI, the lock, the timer pass and the app's request handlers;
kept out of ``_actions`` so the handlers can import it without a cycle.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Final

from book_guard import _ledger
from book_guard._anchor import find_span
from book_guard._books import register
from book_guard._claude import DEFAULT_MODEL
from book_guard._flock import exclusive
from book_guard._openlibrary import BookInfo, lookup_isbn
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
) -> str:
    """Look ``isbn`` up and register it; returns a line for the human.

    An ISBN Open Library does not know is still registered -- with no page
    count, which ``book-guard pages N`` fills in -- so an obscure book never
    blocks reading. Such a book is named by ``title``/``author`` when the
    caller has them, else "ISBN <n>". A network failure registers nothing
    and says so.
    """
    try:
        info = lookup_isbn(isbn)
    except OSError as exc:
        _logger.warning("ISBN lookup for %s failed: %s", isbn, exc)
        return f"Open Library unreachable ({exc}); try again later"
    info = info or BookInfo(
        title=title or f"ISBN {isbn}", author=author, pages=None, isbn=isbn
    )
    book = register(paths, info, pages=pages)
    tail = (
        f", last page {book.pages}"
        if book.pages
        else "; set the last page of your copy (app, or: book-guard pages N)"
    )
    return f"Now reading: {book.label}{tail}"


def quiz_one(
    paths: Paths, view: SessionView, summary: str, *, model: str = DEFAULT_MODEL
) -> Verdict:
    """Grade one summary and record the verdict. Raises if Claude is down."""
    span = find_span(paths, view.book.isbn if view.book else "", view.session)
    _logger.info("grading %s: book text %s", view.session.session_id, span.reason)
    verdict = grade(view.book, view.session, summary, model=model, span=span.text)
    with exclusive(paths):
        if _ledger.load(paths.ledger, paths.key_file).has(view.session.session_id):
            return Verdict(passed=False, feedback="This session was already graded.")
        record_verdict(paths, view.book, view.session, verdict, summary)
    write_next_file(paths, snapshot(paths))
    return verdict
