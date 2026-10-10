# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The rules, as numbers. Every threshold the spec fixed lives here once."""

from __future__ import annotations

from datetime import date, timedelta
from typing import Final

GATE_START_DATE: Final = date(2026, 10, 1)
"""No lock and no debt before this. September is never owed."""

PACE_START_DATE: Final = date(2026, 10, 2)
"""The first day with a page quota: the weekly pace was set on this day, so
2026-10-01 (gated, but before the quotas existed) owes nothing."""

WORKDAY_PAGES: Final = 20
OFFDAY_PAGES: Final = 40
"""Each counted (non-free) day's share of its month's target:
:data:`WORKDAY_PAGES` on ``freedays.WORKDAYS`` (Tue-Thu), :data:`OFFDAY_PAGES`
on Fri-Mon -- 220 a week, the long weekend doing the heavy lifting while
workdays keep the book moving. From :data:`MONTHLY_GOAL_START` they are only
weights: the month's :data:`MONTHLY_PAGES` is split over its counted days in
this 20:40 ratio."""

MONTHLY_PAGES: Final = 1000
"""Each month's goal from :data:`MONTHLY_GOAL_START`, before the year's carry."""

MONTHLY_GOAL_START: Final = date(2026, 10, 1)
"""The first month at :data:`MONTHLY_PAGES`: October 2026 itself, switched on
2026-10-10 at the reader's request (the line rose by 8 pages that day)."""

DAILY_PASS_PAGES: Final = 20
"""Pages credited on one day (summed across sessions, by the day the reading
ended) that open the lock for the rest of that day even while behind the
pace line: reading anything beats reading nothing. It clears the lock only --
it earns no bonus; the debt stays and is spread over the month's remaining
counted days."""

MIN_SECONDS_PER_PAGE: Final = 50
"""A session faster than this is page-flipping, not reading."""

MAX_SESSION: Final = timedelta(hours=6)
"""A start photo older than this cannot open a session with a later end
photo: a stale start would make any end photo look like hours of reading."""

MAX_UPLOAD_DELAY: Final = timedelta(days=7)
"""A photo uploaded more than a week after it was taken is not evidence of
the session it claims to be from. A week, not a day: the app is offline-first
and queues photos while the PC is off, and the EXIF capture time -- not the
upload -- is the session clock."""

GRADER_GRACE: Final = timedelta(hours=1)
"""How long a summary waits on an unreachable grader (outage, usage cap)
before it is credited ungraded -- short enough to keep the evening's bonus.
Claude being down must never make the app useless."""

BONUS_MIN_PAGES: Final = 15
BONUS_MIN_MINUTES: Final = 15
"""One credited session at least this big earns the day's reading hour in
screen-locker (shutdown) and steam-backlog-enforcer (gaming)."""

PACE_BONUS_MIN_PAGES: Final = 10
PACE_BONUS_MIN_MINUTES: Final = 10
"""The smaller bar for a reader who is on the pace line once the session is
counted: being ahead earns the same hour, but a few flipped pages still do not."""

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
