# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""How much of a day's reading target is done, as a signed ``progress`` row.

Written at each credit, inside the ledger lock that appends it, so a later
release of ``earned_time`` can pay the reading bonus in proportion (half the
pages, half the bonus) without judging pace itself. ``progress:<day>:<done>:
<target>`` carries both numbers, so a credit that raises ``done`` writes a new
row and one that changes nothing (capped at the target) writes none.

Inert: nothing in the gate reads a ``progress`` row back. The decision, the
balance and the month debt come from ``credit`` rows alone, so deleting the
ledger earns nothing and a forged row moves nothing.

* ``done`` is the day's credited pages (the rows dated by when the reading
  ended, the same sum :func:`book_guard._bonus.reaches_requirement` uses),
  capped at ``target``. Pages repaid later against the month debt sit on the
  later day's credit rows, so they never back-fill an earlier day.
* ``target`` is :func:`book_guard._bonus.day_requirement`, derived from the
  signed ledger -- never the unsigned copy in ``state.json``.
* No row when ``done`` or ``target`` is 0 (a day asking nothing is the
  auto-grant's), nor for a day before :data:`QUOTA_SWITCH_DATE`.
* A failure writing the row is logged at error and swallowed: the credit it
  follows is the fact that matters and is already on disk.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Final

from book_guard._bonus import day_requirement
from book_guard._constants import QUOTA_SWITCH_DATE
from book_guard._ledger import CREDIT, PROGRESS, Entry, append, load

if TYPE_CHECKING:
    from datetime import date

    from book_guard._ledger import Ledger
    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

SOURCE: Final = "reading"


def progress_entry(ledger: Ledger, day: date) -> Entry | None:
    """The progress row for ``day`` as ``ledger`` stands, ``None`` for no row."""
    if day < QUOTA_SWITCH_DATE:
        return None
    iso = day.isoformat()
    target = day_requirement(ledger, day)
    pages = sum(e.amount for e in ledger.of_kind(CREDIT) if e.day == iso)
    done = min(pages, target)
    if done <= 0 or target <= 0:
        return None
    return Entry(
        entry_id=f"{PROGRESS}:{iso}:{done}:{target}",
        kind=PROGRESS,
        day=iso,
        detail={
            "source": SOURCE,
            "for_day": iso,
            "done": str(done),
            "target": str(target),
        },
    )


def record(paths: Paths, day: date) -> Entry | None:
    """Append ``day``'s progress row (the caller holds the ledger lock).

    Returns the row, ``None`` when there is none to write, it is already
    there, or writing failed -- which never raises, see the module docstring.
    """
    try:
        entry = progress_entry(load(paths.ledger, paths.key_file), day)
        if entry is None or not append(paths.ledger, paths.key_file, entry):
            return None
    except Exception:  # pylint: disable=broad-exception-caught  # credit is on disk
        _logger.exception("progress row for %s not written; the credit stands", day)
        return None
    return entry
