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

from book_guard._photos import MANUAL_START_NAME
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
    "stop": " (where they STOPPED -- the last page read)",
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
    lines = [
        f"Book: {title} (ISBN {book.isbn if book else 'unknown'}).",
        (
            f"The reader read pages {session.start.page}-{session.end.page}"
            f" ({session.pages} pages). They photographed the page they started"
            f" on{', a check page in between,' if session.check else ''}"
            " and the page where they STOPPED -- the stop page was read too."
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
        if p is not None and p.name != MANUAL_START_NAME
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
    """How a first summary is judged: PASS unless it is off-topic.

    kuhy, 2026-11-24: every one of the 7 real fails was a false alarm --
    "only what the photos show", "too broad", "add the specific details".
    So the photo test (STEP 1 until then) and "generic" are gone: a summary
    fails only for another book or part, or for contradicting the text.
    """
    source = "the book's text above" if has_text else "the photographed pages"
    between = (
        " Use the book's text to see what lies between the photographed pages."
        if has_text
        else ""
    )
    return [
        (
            "Judge only whether the summary is about these pages of this book."
            " Pace and time are checked elsewhere: never judge them. A summary"
            " of dozens of pages leaves out most details: never fail it for"
            " omitting anything, for staying with broad themes, or because its"
            " claims are also on the photographed pages. Remarks about their own"
            " reading (e.g. that they did not read the stop page) are not"
            " content: ignore them."
        ),
        (
            "PASS unless one of two things holds. (1) It is off-topic"
            + (
                " -- being about the right book is not enough, a summary of its"
                " other chapters is off-topic too: nothing in it matches the"
                " book's text above (another part of the book, or another"
                " book)."
                if has_text
                else ": it is plainly about another book or subject. You see"
                " only the first and last page: content that is not on them"
                " is the pages between, never a sign of another part."
            )
            + f" (2) It clearly contradicts {source} (a direct conflict -- not"
            " a detail you cannot find)." + between + " Minor inaccuracies,"
            " imperfect recall, typos, an informal tone and any language (e.g."
            " Polish) are fine."
        ),
        MISSING,
    ]


LOCAL_REMINDER: Final = (
    "\n\nREMINDER before you answer: you see only the first and last page, so"
    " most of a real summary is on pages you have not seen -- expected, never"
    " a reason to fail. PASS unless the summary is plainly about another book"
    " or subject, or directly contradicts the photographed pages. A short,"
    " vague or broad summary still PASSES."
    ' Add two fields to the JSON: "other_book": true|false (true only when it'
    " is about a different book or subject: other people, places and events"
    " than this book's -- the same people at another time is this book) and"
    ' "contradicts": "" -- or, only for a direct conflict, the words of the'
    " photographed page that the summary conflicts with, copied exactly;"
    " something you cannot find there is no conflict."
)
"""Appended only for the local fallback grader (:mod:`book_guard._local`)
when it has only the photos: measured 2026-10-15 on the reader's 15 real
summaries, both local qwen3 models failed genuine ones *because* they went
past the photos -- the rule read backwards. 2026-11-27: asked "off_topic",
qwen3 still failed a real Tiananmen summary of a Xi biography (pp. 151-203)
because the photos did not show it; it now names only another book.
Haiku's prompt is untouched."""

LOCAL_REMINDER_TEXT: Final = (
    "\n\nREMINDER before you answer: PASS unless the summary is about another"
    " book or another part of this one, or directly contradicts the text. A"
    " short, vague or broad summary that leaves out most events still PASSES"
    " when it is about these pages; missing details and claims that are also"
    " on the photographed pages are never a reason to fail."
    ' Add two fields to the JSON: "off_topic": true|false (nothing in it'
    " matches the book's text above: another book or another part of this"
    ' one) and "contradicts": "" -- or, only for a direct conflict, the words'
    " of the text above that the summary conflicts with, copied exactly."
)
"""The local reminder when the book's text is in the prompt: with it the
grader can tell another part of the book, so "off_topic" asks for that."""


def local_reminder(*, has_text: bool) -> str:
    """The reminder the local grader gets after a first photo summary."""
    return LOCAL_REMINDER_TEXT if has_text else LOCAL_REMINDER
