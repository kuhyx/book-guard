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
"""Before :data:`QUOTA_SWITCH_DATE`: each counted (non-free) day's weight,
:data:`WORKDAY_PAGES` on ``freedays.WORKDAYS`` (Tue-Thu), :data:`OFFDAY_PAGES`
on Fri-Mon. The month's :data:`MONTHLY_PAGES` was split over its counted days
in this 20:40 ratio; days before the switch keep those quotas."""

QUOTA_SWITCH_DATE: Final = date(2026, 10, 12)
"""From this day (a Monday) the month is split by :data:`MIDWEEK_WEIGHT`,
:data:`EDGE_WEIGHT` and :data:`WEEKEND_WEIGHT`, surplus comes off Mon-Fri,
debt goes onto weekends, and the day's bonus is earned by reading the day's
requirement. The line at its start is the old plan's line exactly: the rest
of October's target is re-split over Oct 12-31, nothing jumps."""

RESPLIT_DATE: Final = date(2026, 10, 18)
"""From this day (a Sunday) one number per day decides everything: each
morning what is left of the month's target (less the pages read) is re-split
by weight over the days left that are not sick, today included, so a
surplus lowers and a debt raises every later day alike, weekends capped.
Today's share is today's requirement: reading it is on pace, opens the lock
and earns the hour. The lock goes on only for a day whose yesterday missed
its requirement; the 20-page pass and the weekend-only debt are gone."""

MIDWEEK_WEIGHT: Final = 15
EDGE_WEIGHT: Final = 30
WEEKEND_WEIGHT: Final = 50
"""From :data:`QUOTA_SWITCH_DATE`, a counted day's weight: Tue/Wed/Thu 15,
Mon/Fri 30, Sat/Sun 50. Only the ratio matters: each month's target is
rescaled over its counted days (weekends capped at :data:`WEEKEND_CAP_PAGES`)."""

WEEKEND_CAP_PAGES: Final = 60
"""No Sat/Sun asks for more than this, base quota plus debt. A month whose
rescale would push its weekends higher pins them at 60 and spreads the rest
over Mon-Fri (still 15:30); debt that no weekend can hold carries into the
next month through the year balance."""

MONTHLY_PAGES: Final = 1000
"""Each month's goal from :data:`MONTHLY_GOAL_START`, before the year's carry."""

MONTHLY_GOAL_START: Final = date(2026, 10, 1)
"""The first month at :data:`MONTHLY_PAGES`: October 2026 itself, switched on
2026-10-10 at the reader's request (the line rose by 8 pages that day)."""

DAILY_PASS_PAGES: Final = 20
"""Pages credited on one day (summed across sessions, by the day the reading
ended) that open the lock for the rest of that day even while behind the
pace line: reading anything beats reading nothing. It clears the lock only --
it earns no bonus; the debt stays, on the month's remaining weekends."""

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

GRADER_GRACE: Final = timedelta(minutes=5)
"""How long a summary waits when no grader answers -- Claude down or out of
usage *and* the local fallback down -- before it is credited ungraded.
Claude being down must never make the app useless (an hour was too long,
2026-10-15)."""

BONUS_MIN_PAGES: Final = 15
BONUS_MIN_MINUTES: Final = 15
"""Before :data:`QUOTA_SWITCH_DATE`: one credited session at least this big
earned the day's reading hour in screen-locker (shutdown) and
steam-backlog-enforcer (gaming). From the switch the hour is earned by the
day's credited pages reaching the day's requirement (``_bonus``)."""

PACE_BONUS_MIN_PAGES: Final = 10
PACE_BONUS_MIN_MINUTES: Final = 10
"""Before :data:`QUOTA_SWITCH_DATE`: the smaller bar for a reader on the pace
line once the session is counted."""

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
