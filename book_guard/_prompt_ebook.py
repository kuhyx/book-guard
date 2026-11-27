# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The grading prompt for a stretch read in the app: the text, no photos.

The photo prompt's first test (is every claim on the three photographed
pages?) has no photos to test here; its counterpart is the opening of the
text, which is all a reader who only looked where they started could
know. Everything else -- leniency, the rewrite deal, the answer -- is the
photo prompt's own wording (:mod:`book_guard._prompt_parts`).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from book_guard._prompt_parts import (
    ANSWER,
    MISSING,
    UNVERIFIABLE,
    rewrite_rules,
)

if TYPE_CHECKING:
    from book_guard._books import Book
    from book_guard._prompt import Context
    from book_guard._sessions import Session


def ebook_prompt(
    book: Book | None, session: Session, summary: str, context: Context
) -> str:
    """The prompt for a stretch read in the app: the text itself, no photos."""
    title = book.label if book else "an unregistered book"
    last_read = int(session.end.page or 0) - 1
    return "\n".join(
        [
            f"Book: {title} (ISBN {book.isbn if book else 'unknown'}).",
            (
                "The reader read this stretch in an e-book reader app, about"
                f" pages {session.start.page}-{last_read} of their paper copy"
                f" ({session.pages} pages; the e-book is another edition, so"
                " page numbers are estimates). Below is exactly the text they"
                " had on screen, from where they started to where they stopped."
            ),
            "--- the text they read ---",
            context.span or "(the text is not available)",
            "--- the reader's summary of what they read ---",
            summary.strip(),
            "---",
            (
                "The text above is the whole stretch, but a summary of dozens of"
                " pages leaves out most of it, and the reader may have read a"
                " little past either end." + UNVERIFIABLE
            ),
            *(
                rewrite_rules(context.checklist)
                if context.checklist
                else _ebook_rules()
            ),
            ANSWER,
        ]
    )


def _ebook_rules() -> list[str]:
    """How a first summary of an in-app stretch is judged."""
    return [
        (
            "Judge only whether the summary is about this text. Pace and time"
            " are checked elsewhere: never judge them. Never fail it for"
            " omitting anything, for staying with broad themes, or because it"
            " draws on the beginning of the text. Remarks about their own"
            " reading are not content: ignore them."
        ),
        (
            "PASS unless it is about another part of the book or another book"
            " (nothing in it matches the text above: knowing the famous plot"
            " is no proof of reading THIS stretch), or it clearly contradicts"
            " the text above (a direct conflict -- not a detail you cannot"
            " find). Minor inaccuracies, imperfect recall, typos, an informal"
            " tone and any language (e.g. Polish) are fine."
        ),
        MISSING,
    ]
