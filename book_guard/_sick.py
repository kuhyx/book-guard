# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The sick days on which book-guard stands down -- the only read of the pool.

A sick day may keep some lockers active (``sickdays`` 0.2.0). One that keeps
``book`` is a normal day here, past or today: it plans its quota, is owed if
unread and locks as usual. So every consumer -- the verdict, the plan, the
bonus requirement, ``ask``, the app's ``pace_inputs`` -- takes this one
filtered set, never ``sickdays.sick_days()`` itself, and none of them can
disagree about what a kept day owes. An unreadable pool reads as no sick day
(the gate applies), as ``sickdays`` guarantees.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import sickdays

if TYPE_CHECKING:
    from datetime import date


def standing_down() -> frozenset[date]:
    """Every sick day that does not keep ``book``."""
    return frozenset(
        day
        for day in sickdays.sick_days()
        if sickdays.stands_down(sickdays.LOCKER_BOOK, day)
    )
