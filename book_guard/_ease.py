# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Eased days: pages taken off one day's number, owed by the rest of the month.

An ``ease`` row (:data:`book_guard._ledger.EASE`) lowers its day's morning
share from the resplit (:mod:`book_guard._resplit`); the next morning's split
re-spreads the pages over the days left, so the month's target and the year's
balance never shrink for it. Read from the ledger, so every pace caller --
lock, bonus, ``ask``, the app's inputs -- sees the same requirement.
"""

from __future__ import annotations

from datetime import date
import logging
from typing import TYPE_CHECKING, Final

from book_guard._ledger import EASE

if TYPE_CHECKING:
    from book_guard._ledger import Ledger

_logger: Final = logging.getLogger(__name__)


def eased_days(ledger: Ledger) -> dict[date, int]:
    """Pages eased per day: rows with pages and a real day, summed."""
    out: dict[date, int] = {}
    for row in ledger.of_kind(EASE):
        try:
            day = date.fromisoformat(row.day)
        except ValueError:
            _logger.warning("ease row %r has no real day; not counted", row.entry_id)
            continue
        if row.amount > 0:
            out[day] = out.get(day, 0) + row.amount
    return out
