# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Grade a session's summary, and record the verdict in the ledger.

The grader sees what the photos showed -- the transcribed start, check and
end pages -- plus the book's identity, and judges whether the summary reads
like someone who read the pages in between. It is the one place an LLM
adjudicates, because nothing deterministic can tell "read it" from "skimmed
three photos"; every other rule (pace, time per page, upload age) is code.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from typing import TYPE_CHECKING, Final

from book_guard import _ledger
from book_guard._claude import DEFAULT_MODEL, ask
from book_guard._constants import BONUS_MIN_MINUTES, BONUS_MIN_PAGES, MAX_ATTEMPTS
from book_guard._ledger import CREDIT, REJECT, Entry

if TYPE_CHECKING:
    from book_guard._books import Book
    from book_guard._paths import Paths
    from book_guard._sessions import Session

MIN_SUMMARY_CHARS: Final = 150
GRADER_VOTES: Final = 3
"""Independent grading calls per summary; the majority decides."""
_ROLE: Final = {
    "start": " (where they started)",
    "check": " (a check page in the middle)",
    "stop": " (where they STOPPED -- not read, do not expect it)",
}

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
    # A majority of independent calls, run side by side: one Haiku answer is
    # noisy (2026-10-03: the same summary passed twice and failed once).
    with ThreadPoolExecutor(max_workers=GRADER_VOTES) as pool:
        answers = list(
            pool.map(lambda _: ask(_SYSTEM, prompt, model=model), range(GRADER_VOTES))
        )
    votes = [
        Verdict(a.get("passed") is True, str(a.get("feedback") or "")) for a in answers
    ]
    passed = sum(v.passed for v in votes) * 2 > len(votes)
    return next(v for v in votes if v.passed == passed)


def bonus_eligible(session: Session) -> bool:
    """Whether this session earns the day's reading hour."""
    return session.pages >= BONUS_MIN_PAGES and session.minutes >= BONUS_MIN_MINUTES


def attempts_left(verdicts: list[Entry]) -> int:
    """Summaries a session may still have graded, given its verdict rows."""
    if any(e.kind == CREDIT for e in verdicts):
        return 0
    return max(0, MAX_ATTEMPTS - len(verdicts))


def record_verdict(
    paths: Paths, book: Book | None, session: Session, verdict: Verdict, summary: str
) -> Entry | None:
    """Write the credit (pass) or reject (fail) row for ``session``.

    The first verdict's id is the session id; a rewrite's is ``<id>#2``.
    Returns ``None`` (and writes nothing) once no attempt is left. The caller
    holds the ledger lock, so the attempt count cannot race.

    The row's ``day`` is the local day the reading *ended*, and
    ``detail.ended_at`` carries the exact time -- the bonus belongs to the
    evening the pages were read, even when the quiz is taken next morning.
    """
    earlier = (
        _ledger.load(paths.ledger, paths.key_file)
        .verdicts()
        .get(session.session_id, [])
    )
    if not attempts_left(earlier):
        return None
    attempt = len(earlier) + 1
    ended = session.ended_at
    entry = Entry(
        entry_id=session.session_id + (f"#{attempt}" if attempt > 1 else ""),
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
            "started_at": str(int(session.started_at.timestamp())),
            "ended_at": str(int(ended.timestamp())),
            "bonus": "1" if verdict.passed and bonus_eligible(session) else "0",
            "feedback": verdict.feedback[:1500],
            "summary": summary.strip()[:1000],
            "attempt": str(attempt),
        },
    )
    _ledger.append(paths.ledger, paths.key_file, entry)
    return entry
