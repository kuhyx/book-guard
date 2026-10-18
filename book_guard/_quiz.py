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
from dataclasses import dataclass, replace
import logging
from typing import TYPE_CHECKING, Final

from book_guard import _errlog, _ledger, _local, _paths
from book_guard._bonus import earns, qualifies
from book_guard._claude import DEFAULT_MODEL, ClaudeUnavailableError, ask
from book_guard._ledger import CREDIT, REJECT, Entry
from book_guard._prompt import (
    LOCAL_REMINDER,
    MAX_MISSING,
    SYSTEM,
    Context,
    build_prompt,
)

if TYPE_CHECKING:
    from book_guard._books import Book
    from book_guard._paths import Paths
    from book_guard._sessions import Session

_logger: Final = logging.getLogger(__name__)

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
    """Credited without a grader: none answered for :data:`GRADER_GRACE`."""
    grader: str = ""
    """Who judged it: ``claude:<model>`` or ``local:<model>``."""
    votes: tuple[bool, ...] = ()
    """Each grading call's pass/fail, in order."""


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
    call. When Claude cannot answer (outage, usage cap) every vote is
    re-cast on the local model -- all of them, so a verdict never mixes two
    graders. Raises ``ClaudeUnavailableError`` only when neither answers --
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
    grader = f"claude:{model}"
    try:
        with ThreadPoolExecutor(max_workers=GRADER_VOTES) as pool:
            answers = list(
                pool.map(
                    lambda _: ask(SYSTEM, prompt, model=model), range(GRADER_VOTES)
                )
            )
    except ClaudeUnavailableError as exc:
        _logger.warning("Claude did not grade (%s); asking %s", exc, _local.LOCAL_MODEL)
        grader = f"local:{_local.LOCAL_MODEL}"
        # One after another: the card holds one copy of the model.
        rewrite = bool(context and context.checklist)
        local_prompt = prompt + ("" if rewrite else LOCAL_REMINDER)
        answers = [_local.ask_local(SYSTEM, local_prompt) for _ in range(GRADER_VOTES)]
        # Graded after all: nothing waits on Claude, so the app stops saying so.
        _errlog.claude_ok(_paths.paths())
    votes = [_vote(a) for a in answers]
    passed = sum(v.passed for v in votes) * 2 > len(votes)
    chosen = next(v for v in votes if v.passed == passed)
    return replace(chosen, grader=grader, votes=tuple(v.passed for v in votes))


def _vote(answer: dict[str, object]) -> Verdict:
    """One grader answer; a pass carries no missing list."""
    passed = answer.get("passed") is True
    raw = answer.get("missing")
    items = [str(m).strip() for m in raw] if isinstance(raw, list) else []
    missing = () if passed else tuple(m for m in items if m)[:MAX_MISSING]
    return Verdict(passed, str(answer.get("feedback") or ""), missing)


def bonus_eligible(session: Session, *, on_pace: bool = False) -> bool:
    """Whether this session earned the day's reading hour by size alone.

    The rule before :data:`QUOTA_SWITCH_DATE`; from it the day's requirement
    decides (:func:`book_guard._bonus.reaches_requirement`).

    ``on_pace`` is the smaller bar for a reader on the pace line; the pace
    itself is judged in :func:`record_verdict`, where the ledger is at hand.
    """
    return qualifies(session.pages, session.minutes, on_pace=on_pace)


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
    ledger = _ledger.load(paths.ledger, paths.key_file)
    earlier = ledger.verdicts().get(session.session_id, [])
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
            "bonus": "0",
            "feedback": verdict.feedback[:1500],
            "summary": summary.strip()[:1000],
            "attempt": str(attempt),
            "missing": "\n".join(verdict.missing),
            "graded": "0" if verdict.ungraded else "1",
            "grader": verdict.grader,
        },
    )
    if verdict.passed and earns(session.pages, session.minutes, ledger, entry):
        entry = replace(entry, detail={**entry.detail, "bonus": "1"})
    _ledger.append(paths.ledger, paths.key_file, entry)
    return entry
