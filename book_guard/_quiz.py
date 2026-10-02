# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Grade a session's summary, and record the verdict in the ledger.

The grader sees what the photos showed -- the transcribed start, check and
end pages -- plus the book's identity, and judges whether the summary reads
like someone who read the pages in between. It is the one place an LLM
adjudicates, because nothing deterministic can tell "read it" from "skimmed
three photos"; every other rule (pace, time per page, upload age) is code.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Final

from book_guard import _ledger
from book_guard._claude import DEFAULT_MODEL, ask
from book_guard._constants import BONUS_MIN_MINUTES, BONUS_MIN_PAGES
from book_guard._ledger import CREDIT, REJECT, Entry

if TYPE_CHECKING:
    from book_guard._books import Book
    from book_guard._paths import Paths
    from book_guard._sessions import Session

MIN_SUMMARY_CHARS: Final = 150

_SYSTEM: Final = (
    "You check whether a person really read a stretch of a printed book, "
    "from their own short summary. You are fair but not gullible. You "
    "answer with one JSON object and nothing else."
)


@dataclass(frozen=True)
class Verdict:
    """The grader's answer."""

    passed: bool
    feedback: str


def build_prompt(
    book: Book | None, session: Session, summary: str, *, span: str = ""
) -> str:
    """The grading prompt: identity, photographed evidence, then the summary."""
    title = book.label if book else "an unregistered book"
    lines = [
        f"Book: {title} (ISBN {book.isbn if book else 'unknown'}).",
        (
            f"The reader says they read pages {session.start.page}-"
            f"{session.end.page} ({session.pages} pages) in {session.minutes} minutes."
        ),
        "Transcribed text of the pages they photographed during the session:",
    ]
    lines.extend(
        f"--- page {p.page} ---\n{p.text or '(no legible text)'}"
        for p in session.evidence
    )
    if span:
        lines += [
            (
                "--- the book's own text for this stretch (from a digital edition,"
                " located by matching the photos; it may be another language or"
                " edition, so wording and page breaks can differ) ---"
            ),
            span,
        ]
    lines += [
        "--- the reader's summary of what they read ---",
        summary.strip(),
        "---",
        "PASS if the summary is specific and consistent with "
        + (
            "the book's text above"
            if span
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
        (
            'Answer ONLY with JSON: {"passed": true|false, "feedback": "<one or '
            'two sentences addressed to the reader>"}'
        ),
    ]
    return "\n".join(lines)


def grade(
    book: Book | None,
    session: Session,
    summary: str,
    *,
    model: str = DEFAULT_MODEL,
    span: str = "",
) -> Verdict:
    """Grade ``summary`` for ``session``.

    A summary shorter than :data:`MIN_SUMMARY_CHARS` fails without a model
    call. Raises ``ClaudeUnavailableError`` when the grader cannot answer --
    the caller keeps the session open rather than failing it.
    """
    if len(summary.strip()) < MIN_SUMMARY_CHARS:
        return Verdict(
            passed=False,
            feedback=f"Write at least {MIN_SUMMARY_CHARS} characters (3-5 sentences).",
        )
    prompt = build_prompt(book, session, summary, span=span)
    answer = ask(_SYSTEM, prompt, model=model)
    return Verdict(answer.get("passed") is True, str(answer.get("feedback") or ""))


def bonus_eligible(session: Session) -> bool:
    """Whether this session earns the day's reading hour."""
    return session.pages >= BONUS_MIN_PAGES and session.minutes >= BONUS_MIN_MINUTES


def record_verdict(
    paths: Paths, book: Book | None, session: Session, verdict: Verdict, summary: str
) -> Entry:
    """Write the credit (pass) or reject (fail) row for ``session``.

    The row's ``day`` is the local day the reading *ended*, and
    ``detail.ended_at`` carries the exact time -- the bonus belongs to the
    evening the pages were read, even when the quiz is taken next morning.
    """
    ended = session.end.taken
    entry = Entry(
        entry_id=session.session_id,
        kind=CREDIT if verdict.passed else REJECT,
        day=ended.astimezone().date().isoformat(),
        amount=session.pages if verdict.passed else 0,
        detail={
            "isbn": book.isbn if book else "",
            "title": book.title if book else "",
            "start_page": str(session.start.page),
            "end_page": str(session.end.page),
            "check_page": str(session.check_page or ""),
            "pages": str(session.pages),
            "minutes": str(session.minutes),
            "started_at": str(int(session.start.taken.timestamp())),
            "ended_at": str(int(ended.timestamp())),
            "bonus": "1" if verdict.passed and bonus_eligible(session) else "0",
            "feedback": verdict.feedback[:1500],
            "summary": summary.strip()[:1000],
        },
    )
    _ledger.append(paths.ledger, paths.key_file, entry)
    return entry
