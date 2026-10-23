# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The grader's prompt: the photos' evidence, the book's text, the summary.

Split out of ``_quiz`` (which grades and records). A failed summary is told
exactly what is missing (1-3 topics, never the answers); each rewrite is
judged only on whether it now covers them -- "add these and it passes".

The grader never sees every page the reader read: without a book file it
gets three photographed pages out of dozens. What it cannot check is
therefore never a reason to fail (2026-10-07: a Xi Jinping summary was
failed twice for "the Olympics and Japan visits are unsupported by the
photographed pages" -- pages it had never been shown).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Final

from book_guard._prompt_ebook import ebook_prompt
from book_guard._prompt_parts import (
    ANSWER,
    MISSING,
    UNVERIFIABLE,
    rewrite_rules,
)

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


@dataclass(frozen=True)
class Context:
    """What the grader gets besides the photos and the summary."""

    span: str = ""
    """The book's own text for the stretch, when a file is attached."""
    checklist: tuple[str, ...] = ()
    """A rewrite: what the previous grading said was missing."""


def build_prompt(
    book: Book | None,
    session: Session,
    summary: str,
    context: Context | None = None,
) -> str:
    """The grading prompt: identity, photographed evidence, then the summary.

    A rewrite (``context.checklist``) is judged against what the previous
    grading asked for, not afresh.
    """
    context = context or Context()
    if session.estimated:
        return ebook_prompt(book, session, summary, context)
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
        "Transcribed text of those photos (OCR: expect garbled words):",
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
        _seen(session, has_text=bool(context.span)),
        *(
            rewrite_rules(context.checklist)
            if context.checklist
            else _rules(has_text=bool(context.span))
        ),
        ANSWER,
    ]
    return "\n".join(lines)


def _seen(session: Session, *, has_text: bool) -> str:
    """What the grader was and was not shown -- the limit of what it can judge."""
    if has_text:
        shown = (
            "The book's text above covers the stretch, but it was located by"
            " matching and may be another edition or language: its edges can be"
            " off by pages, so a detail you do not find in it proves nothing."
        )
    else:
        shown = (
            f"You were shown ONLY {len(session.evidence)} photographed pages, not"
            f" the {session.pages} pages the reader read: most of what a real"
            " reader remembers is on pages you have not seen."
        )
    return shown + UNVERIFIABLE


def _rules(*, has_text: bool) -> list[str]:
    """How a first summary is judged: the photo test first, then leniency.

    The order matters. Stated as one more rule among lenient ones, "built
    only from the photos fails" lost: a fluent cheat written from the three
    photos passed 4 of 4 (2026-10-07). As a step decided first, it holds.
    """
    source = "the book's text above" if has_text else "the photographed pages"
    between = (
        " Use the book's text to see what lies between the photographed pages."
        if has_text
        else ""
    )
    return [
        (
            "Judge only whether the summary shows the reader read these pages."
            " Pace and time are checked elsewhere: never judge them. A summary"
            " of dozens of pages leaves out most details: never fail it for"
            " omitting anything. Remarks about their own reading (e.g. that"
            " they did not read the stop page) are not content: ignore them."
        ),
        (
            "STEP 1, the photo test -- decide it first. Go through the"
            " summary's specific claims and check each against the transcribed"
            " photo text above (start, check AND stop page). If every specific"
            " claim is on those photographed pages, the summary FAILS, however"
            " fluent and accurate: that is exactly what someone writes who only"
            " looked at the three photos." + between
        ),
        (
            "STEP 2, only when the summary also has specific content that is"
            " NOT on the photographed pages (from the pages between them --"
            " what a real reader adds): PASS, unless it is generic (nothing a"
            f" non-reader could not write), clearly contradicts {source} (a"
            " direct conflict -- not a detail you cannot find), or "
            + (
                "nothing in it matches the book's text above (another part of"
                " the book, or another book)."
                if has_text
                else "is plainly about another book or subject."
            )
            + " Alongside such content, things also on the stop page are fine"
            " (a story runs across the page break). Minor inaccuracies,"
            " imperfect recall, typos, an informal tone and any language"
            " (e.g. Polish) are fine."
        ),
        MISSING,
    ]


LOCAL_REMINDER: Final = (
    "\n\nREMINDER before you answer: details that are NOT on the photographed"
    " pages are what a real reader adds -- they are the reason to PASS, never"
    " a reason to fail. FAIL a first summary only when ALL its specific"
    " claims are on the photographed pages, or it is generic, or about"
    " another book or part."
)
"""Appended only for the local fallback grader (:mod:`book_guard._local`):
measured 2026-10-15 on the reader's 15 real summaries, both local qwen3
models failed genuine ones *because* they went past the photos -- the rule
read backwards. Haiku's prompt is untouched."""
