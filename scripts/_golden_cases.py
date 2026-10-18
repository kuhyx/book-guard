# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The scenarios :mod:`scripts.pace_goldens` runs: histories, days, calendars."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta

from book_guard._pace_view import Simulation


@dataclass(frozen=True)
class Case:
    """One scenario: a reading history, a "today", the days to check."""

    name: str
    today: date
    first: date
    last: date
    credits: dict[date, int]
    free: frozenset[date] = frozenset()
    sick: frozenset[date] = frozenset()
    sim: Simulation | None = None
    note: str = ""


def span(first: date, last: date) -> list[date]:
    """Every day from ``first`` through ``last``."""
    return [first + timedelta(days=i) for i in range((last - first).days + 1)]


def _reading(
    first: date, last: date, low: int, high: int, seed: int
) -> dict[date, int]:
    """Deterministic pseudo-random pages a day in ``[low, high]``, some days 0."""
    out: dict[date, int] = {}
    for d in span(first, last):
        n = (d.toordinal() * 7919 + seed * 104729) % 97
        if n % 7 == 0:
            continue
        out[d] = low + n % (high - low + 1)
    return out


_DEMO = {
    date(2026, 10, 2): 44,
    date(2026, 10, 3): 53,
    date(2026, 10, 4): 47,
    date(2026, 10, 7): 69,
    date(2026, 10, 8): 17,
    date(2026, 10, 15): 22,
}
"""The sandbox ledger's credits: far behind, weekends at the cap."""

_AHEAD = _reading(date(2026, 10, 2), date(2026, 10, 19), 40, 70, 1)
"""Reading well past the line: surplus comes off the remaining Mon-Fri."""


def cases() -> list[Case]:
    """Every scenario the fixture holds, in order."""
    low = _reading(date(2026, 10, 2), date(2026, 12, 19), 0, 30, 2)
    steady = _reading(date(2026, 10, 2), date(2027, 1, 24), 25, 45, 3)
    return [
        Case(
            "october-switch-debt",
            date(2026, 10, 15),
            date(2026, 10, 1),
            date(2026, 11, 30),
            _DEMO,
            note="far behind: debt fills weekends to 60, the rest carries",
        ),
        Case(
            "october-surplus",
            date(2026, 10, 20),
            date(2026, 10, 1),
            date(2026, 11, 30),
            _AHEAD,
            note="ahead: Mon-Fri requirements shrink, weekends keep theirs",
        ),
        Case(
            "november-free-days",
            date(2026, 11, 10),
            date(2026, 11, 1),
            date(2026, 12, 31),
            _reading(date(2026, 10, 2), date(2026, 11, 9), 20, 50, 4),
            free=frozenset(
                {
                    date(2026, 10, 9),
                    date(2026, 11, 11),
                    date(2026, 11, 12),
                    date(2026, 11, 20),
                    date(2026, 11, 21),
                    date(2026, 12, 24),
                }
            ),
        ),
        Case(
            "december-to-january",
            date(2026, 12, 20),
            date(2026, 12, 14),
            date(2027, 1, 31),
            low,
            note="behind all year: January takes December's whole balance",
        ),
        Case(
            "february-weekend-cap",
            date(2027, 1, 25),
            date(2027, 1, 18),
            date(2027, 3, 7),
            steady,
            note="February's split would ask >60 of a weekend: pinned at 60",
        ),
        Case(
            "simulate-minus-weekend",
            date(2026, 10, 20),
            date(2026, 10, 19),
            date(2026, 11, 8),
            _AHEAD,
            sim=Simulation(date(2026, 10, 24), -20),
            note="20 short on a Saturday: the debt lands on later weekends",
        ),
        Case(
            "simulate-minus-tomorrow",
            date(2026, 10, 15),
            date(2026, 10, 15),
            date(2026, 11, 8),
            _DEMO,
            sim=Simulation(date(2026, 10, 16), -20),
            note="weekends already at 60: the 20 carries into November",
        ),
        Case(
            "simulate-plus-today",
            date(2026, 10, 20),
            date(2026, 10, 19),
            date(2026, 11, 8),
            _AHEAD,
            sim=Simulation(date(2026, 10, 20), 40),
        ),
        Case(
            "simulate-minus-debt",
            date(2026, 10, 15),
            date(2026, 10, 15),
            date(2026, 11, 8),
            _DEMO,
            sim=Simulation(date(2026, 10, 15), -20),
            note="below what today already credited: a negative synthetic row",
        ),
        Case(
            "simulate-plus-weekend",
            date(2026, 11, 10),
            date(2026, 11, 10),
            date(2026, 12, 6),
            _reading(date(2026, 10, 2), date(2026, 11, 9), 10, 30, 5),
            sim=Simulation(date(2026, 11, 14), 25),
        ),
        Case(
            "sick-weekday-and-weekend",
            date(2026, 10, 20),
            date(2026, 10, 19),
            date(2026, 11, 8),
            _AHEAD,
            sick=frozenset({date(2026, 10, 22), date(2026, 10, 25)}),
            note="ahead: a Thu and a Sun ask nothing, the days left carry their share",
        ),
        Case(
            "sick-weekend-with-debt",
            date(2026, 10, 15),
            date(2026, 10, 15),
            date(2026, 11, 8),
            _DEMO,
            sick=frozenset({date(2026, 10, 17)}),
            sim=Simulation(date(2026, 10, 17), 12),
            note="behind: the debt skips the sick Saturday; 12 read on it count",
        ),
        Case(
            "sick-last-month",
            date(2026, 11, 10),
            date(2026, 10, 19),
            date(2026, 11, 30),
            _reading(date(2026, 10, 2), date(2026, 11, 9), 20, 50, 6),
            sick=frozenset({date(2026, 10, 21), date(2026, 10, 27)}),
            note="October's sick shares are still owed: November's carry is whole",
        ),
        Case(
            "sick-before-the-resplit",
            date(2026, 10, 19),
            date(2026, 10, 15),
            date(2026, 10, 31),
            _reading(date(2026, 10, 2), date(2026, 10, 18), 20, 40, 7),
            sick=frozenset({date(2026, 10, 16)}),
            note="the share the old rules dropped on Oct 16 is owed from Oct 18",
        ),
        Case(
            "sick-to-month-end",
            date(2026, 11, 3),
            date(2026, 10, 25),
            date(2026, 11, 8),
            _reading(date(2026, 10, 2), date(2026, 10, 24), 20, 40, 8),
            sick=frozenset(span(date(2026, 10, 25), date(2026, 10, 31))),
            note="no day left to carry it: the share goes to November's carry",
        ),
    ]
