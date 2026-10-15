# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Re-grade the real, already-judged summaries and compare with their verdicts.

The reader's own summaries in the ledger, each with the verdict it got, are
the realistic test set for a grader (``grader_suite.py`` is the adversarial
one). It rebuilds every session from the photo cache, regrades the recorded
summary with the same checklist the rewrite was promised, and prints
recorded vs now. It never writes the ledger; like any Claude call, the
Claude path logs to ``errors.jsonl`` and clears the outage marker.

    python3 scripts/replay_verdicts.py [MODEL] [--local [--local-model NAME]]
        [--from N] [--count K]

``--from``/``--count`` pick rows (a local row takes ~20 s; keep each call
under a minute). Rows credited ungraded (``graded == "0"``) are skipped:
they have no verdict to agree with.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import sys
from typing import TYPE_CHECKING

from book_guard import _ledger, _local, _photos, _quiz
from book_guard._anchor import find_span
from book_guard._books import book_at
from book_guard._claude import ClaudeUnavailableError
from book_guard._ledger import CREDIT, REJECT
from book_guard._paths import paths
from book_guard._prompt import Context
from book_guard._sessions import build_sessions

if TYPE_CHECKING:
    from book_guard._ledger import Entry, Ledger
    from book_guard._paths import Paths
    from book_guard._sessions import Session


def _out(*parts: object) -> None:
    """A report line on stdout (a script's output, not a log)."""
    sys.stdout.write(" ".join(str(x) for x in parts) + "\n")


def _parse() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", maxsplit=1)[0])
    parser.add_argument("model", nargs="?", default="haiku")
    parser.add_argument("--local", action="store_true", help="Claude down")
    parser.add_argument("--local-model", default="", help="another ollama model")
    parser.add_argument("--from", dest="first", type=int, default=0)
    parser.add_argument("--count", type=int, default=None)
    return parser.parse_args()


def _out_of_usage(*_args: object, **_kwargs: object) -> dict[str, object]:
    msg = "replay_verdicts --local: Claude is out of usage"
    raise ClaudeUnavailableError(msg)


def _judged(entries: list[Entry]) -> list[Entry]:
    """Every graded credit/reject row carrying a summary, in ledger order."""
    return [
        e
        for e in entries
        if e.kind in {CREDIT, REJECT}
        and e.detail.get("summary")
        and e.detail.get("graded") != "0"
    ]


@dataclass(frozen=True)
class _Replay:
    """What every row is graded again against."""

    active: Paths
    ledger: Ledger
    sessions: dict[str, Session]
    model: str


def _regrade(replay: _Replay, index: int, entry: Entry) -> bool:
    """Regrade one row and print it; whether its verdict flipped."""
    sid = entry.entry_id.split("#")[0]
    session = replay.sessions.get(sid)
    if session is None:
        _out(f"{index:2} {entry.entry_id[:34]}  no session in the photo cache")
        return False
    earlier = [
        e
        for e in replay.ledger.verdicts().get(sid, [])
        if e.created_at < entry.created_at
    ]
    last = earlier[-1].detail.get("missing", "") if earlier else ""
    checklist = tuple(line for line in last.split("\n") if line)
    book = book_at(replay.ledger, session.end.taken)
    span = find_span(replay.active, book.isbn, session) if book else None
    verdict = _quiz.grade(
        book,
        session,
        entry.detail["summary"],
        model=replay.model,
        context=Context(span=span.text if span else "", checklist=checklist),
    )
    was = entry.kind == CREDIT
    _out(
        f"{index:2} p.{session.start.page}-{session.end.page}"
        f" {'rewrite' if checklist else 'first  '}"
        f" was {'pass' if was else 'fail'} now"
        f" {'pass' if verdict.passed else 'fail'}"
        f"  {'ok' if verdict.passed == was else 'FLIP'} [{verdict.grader}]"
        f" votes {''.join('P' if v else 'F' for v in verdict.votes)}"
        f"  -- {verdict.feedback[:400]}"
    )
    return verdict.passed != was


def main() -> int:
    """Regrade the chosen rows; exit 1 if any verdict flipped."""
    args = _parse()
    if args.local:
        # The production fallback path; vars(): a script's monkeypatch past Final.
        vars(_quiz)["ask"] = _out_of_usage
        vars(_local)["LOCAL_MODEL"] = args.local_model or _local.LOCAL_MODEL
    active = paths()
    ledger = _ledger.load(active.ledger, active.key_file)
    records = _photos.usable_pages(_photos.load(active.photos))
    replay = _Replay(
        active, ledger, {s.session_id: s for s in build_sessions(records)}, args.model
    )
    rows = _judged(ledger.entries)
    count = len(rows) if args.count is None else args.count
    chosen = rows[args.first : args.first + count]
    flips = sum(_regrade(replay, i, e) for i, e in enumerate(chosen, args.first))
    _out(f"{flips} verdict(s) flipped of {len(chosen)}")
    return 1 if flips else 0


if __name__ == "__main__":
    sys.exit(main())
