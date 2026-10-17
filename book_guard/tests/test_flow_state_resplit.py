# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""From the resplit, one number: today's pages open the lock and earn the hour.

The lock goes on only for a day whose yesterday missed its number, and comes
off the moment today's number is read.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import TYPE_CHECKING

from book_guard import _ledger
from book_guard._constants import RESPLIT_DATE
from book_guard._ledger import CREDIT, Entry
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import add_credit, add_escape

if TYPE_CHECKING:
    from book_guard._paths import Paths

_SUN = RESPLIT_DATE  # Sun 2026-10-18
_MON = _SUN + timedelta(days=1)


def _never(_day: date) -> bool:
    return False


def _required(paths: Paths, day: date) -> int:
    return snapshot(
        paths, today=day, is_free=_never, sick=frozenset()
    ).pace.ask.required


def _missed(paths: Paths, day: date) -> str:
    short = _required(paths, day)
    return f"yesterday was behind pace; {short} more pages today open it"


def test_the_first_day_starts_clean(bg_paths: Paths) -> None:
    # Oct 17 asked 60 under the old rule and got nothing: it does not count.
    snap = snapshot(bg_paths, today=_SUN, is_free=_never, sick=frozenset())
    assert (snap.locked, snap.reason) == (
        False,
        "60 more pages today to stay on pace",
    )


def test_a_missed_yesterday_locks(bg_paths: Paths) -> None:
    snap = snapshot(bg_paths, today=_MON, is_free=_never, sick=frozenset())
    assert (snap.locked, snap.reason) == (True, _missed(bg_paths, _MON))


def test_a_met_yesterday_keeps_today_open(bg_paths: Paths) -> None:
    add_credit(bg_paths, _SUN.isoformat(), _required(bg_paths, _SUN))
    snap = snapshot(bg_paths, today=_MON, is_free=_never, sick=frozenset())
    assert snap.locked is False
    assert snap.reason == f"{snap.pace.ask.required} more pages today to stay on pace"


def test_reading_todays_number_opens_the_lock(bg_paths: Paths) -> None:
    add_credit(bg_paths, _MON.isoformat(), _required(bg_paths, _MON))
    snap = snapshot(bg_paths, today=_MON, is_free=_never, sick=frozenset())
    assert (snap.locked, snap.reason) == (False, "on pace")


def test_one_page_short_stays_locked(bg_paths: Paths) -> None:
    add_credit(bg_paths, _MON.isoformat(), _required(bg_paths, _MON) - 1)
    snap = snapshot(bg_paths, today=_MON, is_free=_never, sick=frozenset())
    assert (snap.locked, snap.reason) == (
        True,
        "yesterday was behind pace; 1 more page today open it",
    )


def test_a_free_yesterday_asks_nothing(bg_paths: Paths) -> None:
    snap = snapshot(bg_paths, today=_MON, is_free=lambda d: d == _SUN, sick=frozenset())
    assert snap.locked is False


def test_a_sick_yesterday_asks_nothing(bg_paths: Paths) -> None:
    snap = snapshot(bg_paths, today=_MON, is_free=_never, sick=frozenset({_SUN}))
    assert snap.locked is False


def test_a_granted_yesterday_counts_as_met(bg_paths: Paths) -> None:
    grant = Entry("bonus:x", CREDIT, _SUN.isoformat(), 0, detail={"bonus": "1"})
    _ledger.append(bg_paths.ledger, bg_paths.key_file, grant)
    snap = snapshot(bg_paths, today=_MON, is_free=_never, sick=frozenset())
    assert snap.locked is False


def test_the_first_of_the_month_checks_last_months_last_day(bg_paths: Paths) -> None:
    nov1 = date(2026, 11, 1)
    snap = snapshot(bg_paths, today=nov1, is_free=_never, sick=frozenset())
    assert (snap.locked, snap.reason) == (True, _missed(bg_paths, nov1))


def test_an_escape_still_opens_a_missed_day(bg_paths: Paths) -> None:
    add_escape(bg_paths, _MON.isoformat())
    snap = snapshot(bg_paths, today=_MON, is_free=_never, sick=frozenset())
    assert (snap.locked, snap.reason) == (
        False,
        "today's lock was skipped with the escape hatch",
    )


def test_a_free_today_opens_a_missed_day(bg_paths: Paths) -> None:
    snap = snapshot(bg_paths, today=_MON, is_free=lambda d: d == _MON, sick=frozenset())
    assert (snap.locked, snap.reason) == (False, "today is a free day")


def test_a_sick_today_opens_a_missed_day(bg_paths: Paths) -> None:
    snap = snapshot(bg_paths, today=_MON, is_free=_never, sick=frozenset({_MON}))
    assert (snap.locked, snap.reason) == (False, "today is a sick day")
