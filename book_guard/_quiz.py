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
from book_guard._constants import BONUS_MIN_MINUTES, BONUS_MIN_PAGES
from book_guard._ledger import CREDIT, REJECT, Entry
from book_guard._prompt import MAX_MISSING, SYSTEM, Context, build_prompt

if TYPE_CHECKING:
    from book_guard._books import Book
    from book_guard._paths import Paths
    from book_guard._sessions import Session

MIN_SUMMARY_CHARS: Final = 150
GRADER_VOTES: Final = 3
"""Independent grading calls per summary; the majority decides."""


@dataclass(frozen=True)
class Verdict:
    """The grader's answer."""

    passed: bool
    feedback: str
    missing: tuple[str, ...] = ()
    """On a fail: what to add for it to pass (topics, not answers)."""
    ungraded: bool = False
    """Credited without a grader: it was unreachable for an hour."""


def grade(
    book: Book | None,
    session: Session,
    summary: str,
    *,
    model: str = DEFAULT_MODEL,
    context: Context | None = None,
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
    prompt = build_prompt(book, session, summary, context)
    # A majority of independent calls, run side by side: one Haiku answer is
    # noisy (2026-10-03: the same summary passed twice and failed once).
    with ThreadPoolExecutor(max_workers=GRADER_VOTES) as pool:
        answers = list(
            pool.map(lambda _: ask(SYSTEM, prompt, model=model), range(GRADER_VOTES))
        )
    votes = [_vote(a) for a in answers]
    passed = sum(v.passed for v in votes) * 2 > len(votes)
    return next(v for v in votes if v.passed == passed)


def _vote(answer: dict[str, object]) -> Verdict:
    """One grader answer; a pass carries no missing list."""
    passed = answer.get("passed") is True
    raw = answer.get("missing")
    items = [str(m).strip() for m in raw] if isinstance(raw, list) else []
    missing = () if passed else tuple(m for m in items if m)[:MAX_MISSING]
    return Verdict(passed, str(answer.get("feedback") or ""), missing)


def bonus_eligible(session: Session) -> bool:
    """Whether this session earns the day's reading hour."""
    return session.pages >= BONUS_MIN_PAGES and session.minutes >= BONUS_MIN_MINUTES


def credited(verdicts: list[Entry]) -> bool:
    """Whether a session is done: a credit row ends its grading for good."""
    return any(e.kind == CREDIT for e in verdicts)


def record_verdict(
    paths: Paths, book: Book | None, session: Session, verdict: Verdict, summary: str
) -> Entry | None:
    """Write the credit (pass) or reject (fail) row for ``session``.

    The first verdict's id is the session id; rewrites are ``<id>#2``,
    ``<id>#3``, ... -- a failed summary may be rewritten any number of times.
    Returns ``None`` (and writes nothing) only when the session is already
    credited: two summaries graded side by side must not both credit its
    pages. The caller holds the ledger lock, so that check cannot race.

    The row's ``day`` is the local day the reading *ended*, and
    ``detail.ended_at`` carries the exact time -- the bonus belongs to the
    evening the pages were read, even when the quiz is taken next morning.
    """
    earlier = (
        _ledger.load(paths.ledger, paths.key_file)
        .verdicts()
        .get(session.session_id, [])
    )
    if credited(earlier):
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
            "missing": "\n".join(verdict.missing),
            "graded": "0" if verdict.ungraded else "1",
        },
    )
    _ledger.append(paths.ledger, paths.key_file, entry)
    return entry
