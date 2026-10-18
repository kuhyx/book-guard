# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Write the golden fixtures the app's Dart port of the plan must match.

The app computes week/month/any-day/simulation views offline with a port of
``_quotas``/``_plan``/``_pace`` (``app/lib/src/pace_plan.dart``). This runs
the Python views (:mod:`book_guard._pace_view`, the same code ``book-guard
ask`` uses) over in-memory ledgers -- several months, free days, surplus,
debt, the weekend cap, the December-to-January carry, sick days, simulations -- and
writes every day's numbers, so a Dart test can demand identical answers.

    python3 -m scripts.pace_goldens [OUT]   # from the repo root

Default OUT: ``app/test/fixtures/pace_goldens.json``. Deterministic: rerun
after any change to the plan and commit the diff with it. Run it as a module:
as a file it imports whichever ``book_guard`` the venv installed, not this tree's.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys
from typing import TYPE_CHECKING, Any

from book_guard._ledger import CREDIT, Entry, Ledger
from book_guard._pace_inputs import rules, view_json
from book_guard._pace_view import views
from scripts._golden_cases import Case, cases, span

if TYPE_CHECKING:
    from datetime import date

_OUT = Path(__file__).resolve().parent.parent / "app/test/fixtures/pace_goldens.json"


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
        span(case.first, case.last),
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
    found = [_run(c) for c in cases()]
    doc = {"generated_by": "scripts/pace_goldens.py", "rules": rules(), "cases": found}
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
    for case in found:
        sys.stdout.write(f"{case['name']}: {len(case['days'])} days\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
