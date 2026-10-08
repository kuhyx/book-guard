# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Who earns the day's reading hour, and the grant for rows written before a rule.

The consumers (screen-locker, steam-backlog-enforcer) only read
``detail.bonus == "1"`` on a ``credit`` row, so the rule lives here and is
stamped into the row when it is written. Rows are signed and never edited: a
session that qualifies under a newer rule gets a separate zero-page ``credit``
row (:func:`regrant`) that carries the flag and moves no pace or debt.
"""

from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING

import freedays

from book_guard._constants import (
    BONUS_MIN_MINUTES,
    BONUS_MIN_PAGES,
    PACE_BONUS_MIN_MINUTES,
    PACE_BONUS_MIN_PAGES,
)
from book_guard._flock import exclusive
from book_guard._ledger import CREDIT, Entry, Ledger, append, load
from book_guard._pace import compute_pace

if TYPE_CHECKING:
    from book_guard._paths import Paths

GRANT_PREFIX = "bonus:"
"""A grant row's id is this plus the credit it grants, so it can never group
with that credit's session in :meth:`Ledger.verdicts` (which splits on ``#``)."""


def qualifies(pages: int, minutes: int, *, on_pace: bool) -> bool:
    """Whether a session this big earns the hour (the smaller bar when on pace)."""
    if on_pace:
        return pages >= PACE_BONUS_MIN_PAGES and minutes >= PACE_BONUS_MIN_MINUTES
    return pages >= BONUS_MIN_PAGES and minutes >= BONUS_MIN_MINUTES


def is_on_pace(ledger: Ledger, credit: Entry) -> bool:
    """Whether the reader is on the pace line once ``credit`` is counted.

    Judged on its day, from the ledger as it stood then: credits on later days
    are left out, so an old session cannot borrow a later session's pages.
    """
    kept = [e for e in ledger.entries if not (e.kind == CREDIT and e.day > credit.day)]
    pace = compute_pace(
        Ledger([*kept, credit]), date.fromisoformat(credit.day), freedays.is_free_day
    )
    return pace.behind == 0


def earns(pages: int, minutes: int, ledger: Ledger, credit: Entry) -> bool:
    """Whether ``credit`` earns the hour: big enough, or smaller but on pace."""
    if qualifies(pages, minutes, on_pace=False):
        return True
    return qualifies(pages, minutes, on_pace=True) and is_on_pace(ledger, credit)


def _number(detail: dict[str, str], key: str) -> int | None:
    value = detail.get(key, "")
    return int(value) if value.isdigit() else None


def regrant(paths: Paths, *, dry_run: bool = False) -> list[Entry]:
    """Append a zero-page bonus row for each credit that now earns the hour.

    Skips a day that already has a bonus, and a credit already granted, so
    running it twice writes nothing the second time. Returns the grant rows
    (written, unless ``dry_run``).
    """
    with exclusive(paths):
        ledger = load(paths.ledger, paths.key_file)
        days = {e.day for e in ledger.of_kind(CREDIT) if e.detail.get("bonus") == "1"}
        granted: list[Entry] = []
        for credit in ledger.of_kind(CREDIT):
            pages = _number(credit.detail, "pages")
            minutes = _number(credit.detail, "minutes")
            if credit.day in days or pages is None or minutes is None:
                continue
            others = Ledger([e for e in ledger.entries if e is not credit])
            if not earns(pages, minutes, others, credit):
                continue
            days.add(credit.day)
            grant = Entry(
                entry_id=GRANT_PREFIX + credit.entry_id,
                kind=CREDIT,
                day=credit.day,
                detail={
                    "isbn": credit.detail.get("isbn", ""),
                    "title": credit.detail.get("title", ""),
                    "pages": "0",
                    "minutes": str(minutes),
                    "ended_at": credit.detail.get("ended_at", ""),
                    "bonus": "1",
                    "graded": credit.detail.get("graded", "1"),
                    "grant_of": credit.entry_id,
                    "feedback": (
                        f"Bonus re-evaluated under the current rule for "
                        f"{pages} pages / {minutes} min; no pages added."
                    ),
                },
            )
            if not dry_run:
                append(paths.ledger, paths.key_file, grant)
            granted.append(grant)
        return granted
