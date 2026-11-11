# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Both ends of a paper session count: the +1 top-up for the old way.

Until 2026-11-11 a paper session was ``stop page - start page`` pages (the
stop page "not read"). It is now ``stop - start + 1``. Signed rows are never
edited, so each session credited the old way gets one separate +1-page
``credit`` row, ``inclusive:<its entry_id>``, dated like the original
(same ``day`` and ``detail.ended_at``) and written by ``book-guard
backfill-inclusive``. A row written under the new rule says so
(``detail.counting == "inclusive"``) and is never topped up. The top-up
carries no bonus; ``regrant`` decides that, separately.
"""

from __future__ import annotations

from collections import Counter
import re
import sys
from typing import TYPE_CHECKING, Final

from book_guard import _ledger, _paths
from book_guard._flock import exclusive
from book_guard._ledger import CREDIT, Entry

if TYPE_CHECKING:
    import argparse

COUNTING: Final = "counting"
"""``detail`` key on session rows written once both ends counted."""
INCLUSIVE: Final = "inclusive"
TOPUP_PREFIX: Final = "inclusive:"
"""A top-up's id is this plus the credit it tops up."""

_PAPER_CREDIT: Final = re.compile(r"session:[0-9a-f]{16}-[0-9a-f]{16}(#\d+)?")
"""A paper session's credit id (a rewritten summary adds ``#<attempt>``)."""


def _topup(credit: Entry) -> Entry:
    """The +1-page row that brings ``credit`` to the inclusive count."""
    return Entry(
        entry_id=TOPUP_PREFIX + credit.entry_id,
        kind=CREDIT,
        day=credit.day,
        amount=1,
        detail={
            "isbn": credit.detail.get("isbn", ""),
            "title": credit.detail.get("title", ""),
            "pages": "1",
            "ended_at": credit.detail.get("ended_at", ""),
            "topup_of": credit.entry_id,
            "feedback": "The stop page counts too: one page added.",
        },
    )


def backfill(active: _paths.Paths, *, dry_run: bool = False) -> list[Entry]:
    """Append the top-up for every session credited the old way, once each.

    Skips in-app (``session:ebook-``) and bonus rows, anything already
    stamped ``counting == "inclusive"`` and a credit that has its top-up, so
    a second run writes nothing. Returns the top-up rows (written unless
    ``dry_run``).
    """
    with exclusive(active):
        ledger = _ledger.load(active.ledger, active.key_file)
        added = [
            _topup(credit)
            for credit in ledger.of_kind(CREDIT)
            if _PAPER_CREDIT.fullmatch(credit.entry_id)
            and credit.detail.get(COUNTING) != INCLUSIVE
            and not ledger.has(TOPUP_PREFIX + credit.entry_id)
        ]
        if not dry_run:
            for row in added:
                _ledger.append(active.ledger, active.key_file, row)
        return added


def configure(parser: argparse.ArgumentParser) -> None:
    """The ``backfill-inclusive`` subcommand's arguments."""
    parser.add_argument("--dry-run", action="store_true")


def cmd(args: argparse.Namespace) -> int:
    """List (or write) the top-ups, per day, and their total."""
    added = backfill(_paths.paths(), dry_run=args.dry_run)
    if not added:
        sys.stdout.write("nothing to add\n")
        return 0
    verb = "would add" if args.dry_run else "added"
    lines = [
        f"{verb} {day} +{count}"
        for day, count in sorted(Counter(row.day for row in added).items())
    ]
    lines.append(f"total +{len(added)} pages in {len(added)} sessions")
    sys.stdout.write("\n".join(lines) + "\n")
    return 0
