# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The grader's prompt: the photos' evidence, the book's text, the summary.

Split out of ``_quiz`` (which grades and records). A failed first summary is
told exactly what is missing (1-3 topics, never the answers); its rewrite is
judged only on whether it now covers them -- "add these and it passes".
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Final

if TYPE_CHECKING:
    from book_guard._books import Book
    from book_guard._sessions import Session

_ROLE: Final = {
    "start": " (where they started)",
    "check": " (a check page in the middle)",
    "stop": " (where they STOPPED -- not read, do not expect it)",
}

SYSTEM: Final = (
    "You check whether a person really read a stretch of a printed book, "
    "from their own short summary. You are fair but not gullible. You "
    "answer with one JSON object and nothing else."
)

MAX_MISSING: Final = 3

_MISSING: Final = (
    f'On a FAIL, list in "missing" 1-{MAX_MISSING} things from THESE pages'
    " whose mention would make you accept it. Name each as a topic or a"
    ' question (e.g. "what he did after arriving in the village"), never the'
    " answer itself. Leave it empty only if no addition could rescue the"
    " summary (it describes another part of the book)."
)

_ANSWER: Final = (
    'Answer ONLY with JSON: {"passed": true|false, "feedback": "<one or two'
    ' sentences addressed to the reader>", "missing": ["<topic>", ...]}'
)


@dataclass(frozen=True)
class Context:
    """What the grader gets besides the photos and the summary."""

    span: str = ""
    """The book's own text for the stretch, when a file is attached."""
    checklist: tuple[str, ...] = ()
    """A rewrite: what the first grading said was missing."""


def build_prompt(
    book: Book | None,
    session: Session,
    summary: str,
    context: Context | None = None,
) -> str:
    """The grading prompt: identity, photographed evidence, then the summary.

    A rewrite (``context.checklist``) is judged against what the first
    grading asked for, not afresh.
    """
    context = context or Context()
    title = book.label if book else "an unregistered book"
    last_read = int(session.end.page or 0) - 1
    lines = [
        f"Book: {title} (ISBN {book.isbn if book else 'unknown'}).",
        (
            f"The reader read pages {session.start.page}-{last_read}"
            f" ({session.pages} pages). They photographed the page they started"
            " on, a check page in between, and the page where they STOPPED --"
            " the stop page was not read."
        ),
        "Transcribed text of those photos:",
    ]
    lines.extend(
        f"--- page {p.page}{_ROLE[role]} ---\n{p.text or '(no legible text)'}"
        for role, p in (
            ("start", session.start),
            ("check", session.check),
            ("stop", session.end),
        )
        if p is not None
    )
    if context.span:
        lines += [
            (
                "--- the book's own text for this stretch (from a digital edition,"
                " located by matching the photos; it may be another language or"
                " edition, so wording and page breaks can differ) ---"
            ),
            context.span,
        ]
    lines += [
        "--- the reader's summary of what they read ---",
        summary.strip(),
        "---",
        *(
            _rewrite_rules(context.checklist)
            if context.checklist
            else _rules(has_text=bool(context.span))
        ),
        _ANSWER,
    ]
    return "\n".join(lines)


def _rules(*, has_text: bool) -> list[str]:
    """How a first summary is judged."""
    return [
        (
            "Judge only whether the summary shows the reader knows what happens"
            " in the pages they read. Pace and time are checked elsewhere: never"
            " judge them. A summary of dozens of pages leaves out most details:"
            " never fail it for omitting any one page or event, and never for"
            " content of the stop page. Details that are not in the photos are"
            " expected -- they come from the pages in between -- and count FOR"
            " the reader unless they contradict the book."
        ),
        (
            "The deciding question: does the summary describe things from the"
            " pages BETWEEN the photos? One built only from what the photos show"
            " -- however fluent -- FAILS; so does one leaning on the stop page."
        ),
        "PASS if the summary is specific and consistent with "
        + (
            "the book's text above"
            if has_text
            else "the photographed pages and (if "
            "you know this book) with what these pages cover"
        )
        + ", and "
        "shows knowledge of content between the photographed pages -- not just "
        "a paraphrase of the transcribed text above. Minor inaccuracies, "
        "imperfect recall and any language (e.g. Polish) are fine.",
        (
            "FAIL if it is generic, contradicts the pages, describes a different "
            "part of the book, or only restates the transcribed text."
        ),
        _MISSING,
    ]


def _rewrite_rules(checklist: tuple[str, ...]) -> list[str]:
    """How a rewrite is judged: the first grading's promise, nothing new."""
    return [
        (
            "This is a REWRITE. The first summary failed, and the grader"
            " promised to accept it once it also covered:"
        ),
        *(f"- {item}" for item in checklist),
        (
            "PASS if the rewrite covers each point -- briefly, in the reader's"
            " own words, any language -- without contradicting the book. Do not"
            " add requirements beyond this list, and never judge pace, time or"
            " the stop page. FAIL only if a point is missing or contradicts the"
            ' book; then list in "missing" exactly the points still missing.'
        ),
    ]
