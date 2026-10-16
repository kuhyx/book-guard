# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``book-guard ask``: what any day asks -- past, today, projected, simulated.

    book-guard ask [--date YYYY-MM-DD] [--week | --month] [--simulate ±N[@DATE]]

``--simulate -20@2026-10-16`` and ``--simulate=-20@2026-10-16`` both work
(Python 3.14's argparse takes ``-20@...`` as a value, not a flag). Display
only: nothing is written.
"""

from __future__ import annotations

from datetime import date, datetime
import logging
import sys
from typing import TYPE_CHECKING, Final

import freedays

from book_guard import _sick
from book_guard._ledger import load
from book_guard._pace_text import detail, row
from book_guard._pace_view import month_of, parse_simulation, views, week_of
from book_guard._paths import paths

if TYPE_CHECKING:
    import argparse

_logger: Final = logging.getLogger(__name__)


def configure(parser: argparse.ArgumentParser) -> None:
    """The ``ask`` subcommand's flags."""
    parser.add_argument(
        "--date", type=date.fromisoformat, help="YYYY-MM-DD (default: today)"
    )
    span = parser.add_mutually_exclusive_group()
    span.add_argument("--week", action="store_true", help="Mon-Sun around the date")
    span.add_argument("--month", action="store_true", help="the date's month")
    parser.add_argument(
        "--simulate",
        metavar="±N[@YYYY-MM-DD]",
        help="read N pages more (or fewer) than assumed on that day (default: "
        "today, never earlier); every later day follows",
    )


def _out(lines: list[str]) -> None:
    sys.stdout.write("\n".join(lines) + "\n")


def cmd_ask(args: argparse.Namespace) -> int:
    """Print one day in full, or its week/month as rows."""
    active = paths()
    today = datetime.now().astimezone().date()
    day = args.date or today
    try:
        sim = parse_simulation(args.simulate, today) if args.simulate else None
    except ValueError as exc:
        _logger.warning("--simulate: %s", exc)
        return 2
    head = [] if sim is None else [f"Simulation: {sim.delta:+d} pages on {sim.day}"]
    ledger = load(active.ledger, active.key_file)
    calendar = (freedays.is_free_day, _sick.standing_down())
    if args.week or args.month:
        days = month_of(day) if args.month else week_of(day)
        found = views(ledger, today, days, calendar, sim)
        _out([*head, *(row(v) for v in found)])
        return 0
    (view,) = views(ledger, today, [day], calendar, sim)
    _out([*head, *detail(view)])
    return 0
