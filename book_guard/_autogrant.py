# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A day that asks no pages earns its reading hour without any reading.

From :data:`QUOTA_SWITCH_DATE`, a day whose requirement is 0 -- a free day,
or a Mon-Fri day whose quota surplus already cut to nothing -- gets the
bonus the moment a periodic run (the inbox pass, the lock gate) sees it: one
signed zero-page ``credit`` row, ``bonus:auto:<day>``, with ``bonus == "1"``
and ``ended_at`` = now, so the consumers' ``reading_match`` counts it for
that day. It moves no pace or debt (no pages), is written once per day, and
not at all on a day that already has a bonus. A sick day asks nothing but
is judged by the requirement it would have had
(:func:`book_guard._bonus.day_requirement`), so being sick never grants it.
"""

from __future__ import annotations

from datetime import datetime
import time
from typing import TYPE_CHECKING, Final

from book_guard._bonus import day_requirement
from book_guard._constants import QUOTA_SWITCH_DATE
from book_guard._flock import exclusive
from book_guard._ledger import CREDIT, Entry, append, load

if TYPE_CHECKING:
    from datetime import date

    from book_guard._paths import Paths

AUTO_PREFIX: Final = "bonus:auto:"
"""An auto-grant row's id is this plus its day: stable, so never written twice."""


def auto_grant(
    paths: Paths,
    *,
    today: date | None = None,
    now: float | None = None,
    dry_run: bool = False,
) -> Entry | None:
    """Grant ``today``'s hour if it asks no pages; return the row (``None``: none).

    Written unless ``dry_run``. Nothing before the switch, nothing on a day
    that already carries a bonus, nothing on a day that asks pages.
    """
    stamp = time.time() if now is None else now
    day = today or datetime.fromtimestamp(stamp).astimezone().date()
    if day < QUOTA_SWITCH_DATE:
        return None
    with exclusive(paths):
        ledger = load(paths.ledger, paths.key_file)
        if any(
            e.day == day.isoformat() and e.detail.get("bonus") == "1"
            for e in ledger.of_kind(CREDIT)
        ):
            return None
        if day_requirement(ledger, day) > 0:
            return None
        grant = Entry(
            entry_id=AUTO_PREFIX + day.isoformat(),
            kind=CREDIT,
            day=day.isoformat(),
            detail={
                "isbn": "",
                "title": "",
                "pages": "0",
                "minutes": "0",
                "ended_at": str(int(stamp)),
                "bonus": "1",
                "graded": "1",
                "auto": "1",
                "feedback": (
                    "Today asks no pages (a free day, or reading ahead already "
                    "covered it): the hour is granted without reading."
                ),
            },
        )
        if not dry_run:
            append(paths.ledger, paths.key_file, grant)
        return grant
