# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The days on which book-guard stands down -- the only read of the pools.

A sick day may keep some lockers active (``sickdays`` 0.2.0). One that keeps
``book`` is a normal day here, past or today: it plans its quota, is owed if
unread and locks as usual. So every consumer -- the verdict, the plan, the
bonus requirement, ``ask``, the app's ``pace_inputs`` -- takes this one
filtered set, never ``sickdays.sick_days()`` itself, and none of them can
disagree about what a kept day owes. An unreadable pool reads as no sick day
(the gate applies), as ``sickdays`` guarantees.

An active focus project (:mod:`book_guard._focus`) stands the gate down the
same way, so its days join the set: asks 0 pages, counts as kept, never locks.
"""

from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

import sickdays

from book_guard import _focus

if TYPE_CHECKING:
    from datetime import date

FOCUS_RADIUS_DAYS = 62
"""Focus days sampled either side of the anchor: the month plus its neighbours."""


def standing_down(anchor: date | None = None) -> frozenset[date]:
    """Every sick day that does not keep ``book``, and every focus day.

    ``anchor`` is the day being judged (default today): focus days are sampled
    within :data:`FOCUS_RADIUS_DAYS` of it.
    """
    sick = frozenset(
        day
        for day in sickdays.sick_days()
        if sickdays.stands_down(sickdays.LOCKER_BOOK, day)
    )
    centre = anchor or datetime.now().astimezone().date()
    return sick | _focus.days_around(centre, FOCUS_RADIUS_DAYS)
