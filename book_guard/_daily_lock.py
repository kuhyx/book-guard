# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The lock from :data:`RESPLIT_DATE`: one question, about yesterday.

A day that missed its number locks the next one until that day's number is
read; a kept day leaves it open. Pure: ledger and pace in, verdict out
(:func:`book_guard._state.snapshot` asks it).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from book_guard._constants import RESPLIT_DATE
from book_guard._pace import compute_pace

if TYPE_CHECKING:
    from collections.abc import Callable
    from datetime import date

    from book_guard._ledger import Ledger
    from book_guard._pace import Pace


def kept(
    ledger: Ledger, day: date, is_free: Callable[[date], bool], *, sick: frozenset[date]
) -> bool:
    """Whether ``day`` kept its pace: the lock's one question about yesterday.

    Kept when it asked nothing (free, sick, read ahead), when its credited
    pages reached its number, or when a credit dated that day carries the
    bonus (a hand grant counts). A day before :data:`RESPLIT_DATE` is
    kept: the one-number rule starts clean.
    """
    if day < RESPLIT_DATE:
        return True
    pace = compute_pace(ledger, day, is_free, sick=sick)
    return pace.ask.bonus or pace.pages_today >= pace.ask.required


def _pages(count: int) -> str:
    return f"{count} more {'page' if count == 1 else 'pages'} today"


def one_number(
    pace: Pace, *, kept_yesterday: bool, sick: bool, free: bool, escaped: bool
) -> tuple[bool, str]:
    """From the resplit: locked only while yesterday missed and today is short."""
    if sick:
        return False, "today is a sick day"
    if free:
        return False, "today is a free day"
    if not pace.behind:
        return False, "on pace"
    if kept_yesterday:
        return False, f"{_pages(pace.behind)} to stay on pace"
    if escaped:
        return False, "today's lock was skipped with the escape hatch"
    return True, f"yesterday was behind pace; {_pages(pace.behind)} open it"
