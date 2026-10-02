# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The rules, as numbers. Every threshold the spec fixed lives here once."""

from __future__ import annotations

from datetime import date, timedelta
from typing import Final

GATE_START_DATE: Final = date(2026, 10, 1)
"""No lock and no debt before this. September is never owed."""

WORKDAY_PAGES: Final = 20
OFFDAY_PAGES: Final = 40
"""Each counted (non-free) day's share of its month's target:
:data:`WORKDAY_PAGES` on ``freedays.WORKDAYS`` (Tue-Thu), :data:`OFFDAY_PAGES`
on Fri-Mon -- 220 a week, the long weekend doing the heavy lifting while
workdays keep the book moving."""

MIN_SECONDS_PER_PAGE: Final = 50
"""A session faster than this is page-flipping, not reading."""

MAX_SESSION: Final = timedelta(hours=6)
"""A start photo older than this cannot open a session with a later end
photo: a stale start would make any end photo look like hours of reading."""

MAX_UPLOAD_DELAY: Final = timedelta(hours=24)
"""A photo uploaded more than a day after it was taken is not evidence of
the session it claims to be from."""

BONUS_MIN_PAGES: Final = 20
BONUS_MIN_MINUTES: Final = 20
"""One credited session at least this big earns the day's reading hour in
screen-locker (shutdown) and steam-backlog-enforcer (gaming)."""

ESCAPES_PER_MONTH: Final = 2
"""Escape-hatch uses allowed per calendar month. An escape forgives the day's
lock; it credits no pages, so the pace deficit stands."""

ESCAPE_PHRASE: Final = (
    "I am skipping my reading today and I accept that the pages still count "
    "against this month"
)

RANK_BOOK_GUARD: Final = 125
"""gatelock arbitration rank: below leetcode-guard (150), above diet-guard
(100). A literal, like leetcode-guard's, so no gatelock release is needed."""

POLL_INTERVAL_MS: Final = 30_000
"""How often the lock re-reads the inbox and the ledger."""

UPLOAD_SETTLE_SECONDS: Final = 5.0
"""A photo modified more recently than this may still be uploading."""

CLAUDE_TIMEOUT_SECONDS: Final = 240
