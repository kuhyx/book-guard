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
from book_guard._claude import DEFAULT_MODEL, ClaudeUnavailableError
from book_guard._constants import MAX_ATTEMPTS
from book_guard._flock import exclusive
from book_guard._grader_wait import stop, waited_out
from book_guard._http import UnavailableError
from book_guard._lookup import lookup_book
from book_guard._openlibrary import BookInfo
from book_guard._prompt import Context
from book_guard._publish import write_next_file
from book_guard._quiz import Verdict, grade, record_verdict
from book_guard._state import snapshot

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._state import SessionView

_logger: Final = logging.getLogger(__name__)

UNGRADED: Final = (
    "The grader was unreachable for over an hour, so this summary is credited"
    " without grading."
)


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


def _checklist(view: SessionView) -> tuple[str, ...]:
    """What the failed first summary was told to add (the rewrite's deal)."""
    last = view.last_verdict
    raw = last.detail.get("missing", "") if last else ""
    return tuple(line for line in raw.split("\n") if line)


def _grade_or_wait(
    paths: Paths, view: SessionView, summary: str, model: str
) -> Verdict:
    """Grade; past the outage grace, credit ungraded. Raises while waiting."""
    sid = view.session.session_id
    span = find_span(paths, view.book.isbn if view.book else "", view.session)
    _logger.info("grading %s: book text %s", sid, span.reason)
    context = Context(span=span.text, checklist=_checklist(view))
    try:
        verdict = grade(view.book, view.session, summary, model=model, context=context)
    except ClaudeUnavailableError:
        if not waited_out(paths, sid):
            raise
        _logger.warning("grader unreachable past the grace: %s credited ungraded", sid)
        verdict = Verdict(passed=True, feedback=UNGRADED, ungraded=True)
    stop(paths, sid)
    return verdict


def _told(verdict: Verdict, attempt: int) -> Verdict:
    """The verdict as the reader hears it: what to add, and whether they may."""
    if verdict.passed:
        return verdict
    parts = [verdict.feedback]
    if verdict.missing:
        parts.append(f"To be accepted, add: {'; '.join(verdict.missing)}.")
    if attempt < MAX_ATTEMPTS:
        parts.append("You may rewrite this summary once; the second verdict is final.")
    return Verdict(passed=False, feedback=" ".join(parts), missing=verdict.missing)


def quiz_one(
    paths: Paths, view: SessionView, summary: str, *, model: str = DEFAULT_MODEL
) -> Verdict:
    """Grade one summary and record the verdict.

    A fail names what is missing; a first one leaves one rewrite, judged on
    exactly that. While the grader is unreachable this raises (the request
    waits) -- for up to :data:`GRADER_GRACE`, then the summary is credited
    ungraded.
    """
    verdict = _grade_or_wait(paths, view, summary, model)
    with exclusive(paths):
        entry = record_verdict(paths, view.book, view.session, verdict, summary)
    if entry is None:
        return Verdict(passed=False, feedback="This session was already graded.")
    write_next_file(paths, snapshot(paths))
    return _told(verdict, int(entry.detail["attempt"]))
