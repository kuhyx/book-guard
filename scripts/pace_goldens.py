# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Write the golden fixtures the app's Dart port of the plan must match.

The app computes week/month/any-day/simulation views offline with a port of
``_quotas``/``_plan``/``_pace`` (``app/lib/src/pace_plan.dart``). This runs
the Python views (:mod:`book_guard._pace_view`, the same code ``book-guard
ask`` uses) over in-memory ledgers -- several months, free days, surplus,
debt, the weekend cap, the December-to-January carry, sick days, simulations -- and
writes every day's numbers, so a Dart test can demand identical answers.

    python3 scripts/pace_goldens.py [OUT]

Default OUT: ``app/test/fixtures/pace_goldens.json``. Deterministic: rerun
after any change to the plan and commit the diff with it.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
import json
from pathlib import Path
import sys
from typing import Any

from book_guard._ledger import CREDIT, Entry, Ledger
from book_guard._pace_inputs import rules, view_json
from book_guard._pace_view import Simulation, views

_OUT = Path(__file__).resolve().parent.parent / "app/test/fixtures/pace_goldens.json"


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


def _span(first: date, last: date) -> list[date]:
    return [first + timedelta(days=i) for i in range((last - first).days + 1)]


def _reading(
    first: date, last: date, low: int, high: int, seed: int
) -> dict[date, int]:
    """Deterministic pseudo-random pages a day in ``[low, high]``, some days 0."""
    out: dict[date, int] = {}
    for d in _span(first, last):
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


def _cases() -> list[Case]:
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
            note="ahead: a Thu and a Sun ask nothing, every other day as before",
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
            note="October's sick shares stay out of November's carry",
        ),
    ]


def _ledger(pages: dict[date, int]) -> Ledger:
    return Ledger(
        [
            Entry(f"g{i}", CREDIT, d.isoformat(), n)
            for i, (d, n) in enumerate(pages.items())
        ]
    )


def _run(case: Case) -> dict[str, Any]:
    found = views(
        _ledger(case.credits),
        case.today,
        _span(case.first, case.last),
        (lambda d: d in case.free, case.sick),
        case.sim,
    )
    return {
        "name": case.name,
        "note": case.note,
        "today": case.today.isoformat(),
        "credits": {d.isoformat(): n for d, n in sorted(case.credits.items())},
        "free_days": sorted(d.isoformat() for d in case.free),
        "sick_days": sorted(d.isoformat() for d in case.sick),
        "simulate": None
        if case.sim is None
        else {"day": case.sim.day.isoformat(), "delta": case.sim.delta},
        "days": [view_json(v) for v in found],
    }


def main(argv: list[str]) -> int:
    """Write the fixture file; print a one-line summary per case."""
    out = Path(argv[0]) if argv else _OUT
    cases = [_run(c) for c in _cases()]
    doc = {"generated_by": "scripts/pace_goldens.py", "rules": rules(), "cases": cases}
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
    for case in cases:
        sys.stdout.write(f"{case['name']}: {len(case['days'])} days\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
