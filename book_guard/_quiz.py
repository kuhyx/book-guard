# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Grade a session's summary, and record the verdict in the ledger.

The grader sees what the photos showed -- the transcribed start, check and
end pages -- plus the book's identity, and judges whether the summary reads
like someone who read the pages in between. It is the one place an LLM
adjudicates, because nothing deterministic can tell "read it" from "skimmed
three photos"; every other rule (pace, time per page, upload age) is code.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import date
import logging
from typing import TYPE_CHECKING, Final

from book_guard import _errlog, _ledger, _local, _paths, _progress
from book_guard._bonus import earns, qualifies
from book_guard._claude import DEFAULT_MODEL, ClaudeUnavailableError, ask
from book_guard._inclusive import COUNTING, INCLUSIVE
from book_guard._ledger import CREDIT, REJECT, Entry
from book_guard._photos import MANUAL_START_NAME, TYPED
from book_guard._prompt import (
    SYSTEM,
    Context,
    build_prompt,
    local_reminder,
)
from book_guard._prompt_parts import MAX_MISSING
from book_guard._votes import claude_known_out, claude_votes, flagged_pass

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
    floor_waived: bool = False
    """The owner's ``accept --ignore-floor`` credited a too-fast session."""


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
        answers = claude_votes(ask, GRADER_VOTES, SYSTEM, prompt, model)
    except ClaudeUnavailableError as exc:
        _logger.warning("Claude did not grade (%s); asking %s", exc, _local.LOCAL_MODEL)
        grader = f"local:{_local.LOCAL_MODEL}"
        answers = _local_answers(session, prompt, context)
    # What a local contradiction must quote: the text the grader was shown.
    source = "\n".join(
        [context.span if context else "", *(p.text for p in session.evidence)]
    )
    votes = [_vote(a, source) for a in answers]
    passed = sum(v.passed for v in votes) * 2 > len(votes)
    winners = [v for v in votes if v.passed == passed]
    # A vote whose feedback was dropped (overturned) speaks last.
    chosen = next((v for v in winners if v.feedback), winners[0])
    return replace(chosen, grader=grader, votes=tuple(v.passed for v in votes))


def _local_answers(
    session: Session, prompt: str, context: Context | None
) -> list[dict[str, object]]:
    """Every vote re-cast on the local model, one after another.

    The card holds one copy of the model. The reminder is about photographed
    pages: an in-app session has none, a rewrite has its checklist.
    """
    rewrite = bool(context and context.checklist)
    reminder = local_reminder(has_text=bool(context and context.span))
    local_prompt = prompt + ("" if rewrite or session.estimated else reminder)
    answers = [_local.ask_local(SYSTEM, local_prompt) for _ in range(GRADER_VOTES)]
    # Graded after all: nothing waits on Claude, so the app stops saying so --
    # unless the outage names its reset (then Claude is skipped until it, and
    # the flag stays to say so).
    if not claude_known_out():
        _errlog.claude_ok(_paths.paths())
    return answers


def _vote(answer: dict[str, object], source: str = "") -> Verdict:
    """One grader answer; a pass carries no missing list.

    A local answer's flags decide over its own verdict
    (:func:`book_guard._votes.flagged_pass`); its feedback then argues the
    side that lost, so it is dropped.
    """
    said = answer.get("passed") is True
    flagged = flagged_pass(answer, source)
    passed = said if flagged is None else flagged
    feedback = str(answer.get("feedback") or "") if passed is said else ""
    raw = answer.get("missing")
    items = [str(m).strip() for m in raw] if isinstance(raw, list) else []
    missing = () if passed else tuple(m for m in items if m)[:MAX_MISSING]
    return Verdict(passed, feedback, missing)


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
            COUNTING: INCLUSIVE,
            "feedback": verdict.feedback[:1500],
            "summary": summary.strip()[:1000],
            "attempt": str(attempt),
            "missing": "\n".join(verdict.missing),
            "graded": "0" if verdict.ungraded else "1",
            "grader": verdict.grader,
        },
    )
    typed = [
        role
        for role, photo in (
            ("start", session.start),
            ("end", session.end),
            ("check", session.check),
        )
        if photo is not None and photo.page_source == TYPED
    ]
    if session.start.name == MANUAL_START_NAME:
        # Opened by ``book-guard start``: no start photo shows it.
        entry = replace(entry, detail={**entry.detail, "start": "manual"})
    if typed:
        # A page the reader typed (no number printed on it): auditable here.
        entry = replace(
            entry,
            detail={
                **entry.detail,
                "page_source": TYPED,
                "typed_photos": ",".join(typed),
            },
        )
    if session.ebook is not None:
        # Read in the app: the pages are the page map's estimate.
        entry = replace(
            entry,
            detail={
                **entry.detail,
                "source": "ebook",
                "estimated": "1",
                "start_offset": str(session.ebook.start_offset),
                "end_offset": str(session.ebook.end_offset),
            },
        )
    if verdict.floor_waived:
        entry = replace(entry, detail={**entry.detail, "floor": "waived"})
    if verdict.passed and earns(session.pages, session.minutes, ledger, entry):
        entry = replace(entry, detail={**entry.detail, "bonus": "1"})
    _ledger.append(paths.ledger, paths.key_file, entry)
    if entry.amount > 0:
        # After the credit is on disk, inside the caller's lock: a failure
        # there is logged and never costs the credit.
        _progress.record(paths, date.fromisoformat(entry.day))
    return entry
