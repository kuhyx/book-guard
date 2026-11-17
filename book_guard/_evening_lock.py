# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The evening gate: lock until the day's reading bonus is paid.

Entry point of ``book-guard lock --evening`` (the chain's book rung). The
normal gate's window, photo/quiz flow and credit pipeline are reused as is;
what changes is the verdict (the reading rung, not the pace), the stand-downs
(none: the morning carrot and tonight's lockdown stamp are ignored), the
display wait (bounded) and the way out ("end evening", exit code 10).
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Final

from gatelock import wait_for_x_server, watch_credit

from book_guard import _ledger, _pictos
from book_guard._autogrant import auto_grant
from book_guard._evening import (
    EXIT_END_EVENING,
    EXIT_NO_X,
    RANK_EVENING,
    X_WAIT_S,
    evening_view,
    reading_paid,
)
from book_guard._evening_view import add_end_control
from book_guard._lock import BookGuardLock
from book_guard._publish import write_next_file
from book_guard._state import Snapshot, snapshot

if TYPE_CHECKING:
    import argparse
    from datetime import date
    import tkinter as tk

    from gatelock import SurfaceInfo

    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)


class EveningLock(BookGuardLock):
    """The book gate's window with the evening verdict and a way out."""

    _rank = RANK_EVENING

    def __init__(
        self,
        paths: Paths,
        snap: Snapshot,
        *,
        production: bool,
        today: date | None = None,
    ) -> None:
        """Arm the lock, then watch the ledger for the bonus row.

        ``today`` pins the clock of the rung check (demos and tests only).
        """
        self.exit_code = 0
        self._today = today
        super().__init__(paths, snap, production=production)
        watch_credit(self.root, [paths.ledger], self._released, self.close)

    def build_surface(self, parent: tk.Misc, surface: SurfaceInfo) -> None:
        """The normal surface plus the end-evening icon (every output)."""
        super().build_surface(parent, surface)
        add_end_control(parent, self._end)

    def _render(self) -> None:
        self._vars.show(evening_view(_pictos.build(self._snap, recent=4), self._snap))

    def _released(self) -> bool:
        return reading_paid(self._paths, self._today) is True

    def _end(self) -> None:
        self.exit_code = EXIT_END_EVENING
        self.close()


def configure_evening(parser: argparse.ArgumentParser) -> None:
    """The ``lock --evening`` flag."""
    parser.add_argument(
        "--evening",
        action="store_true",
        help="evening chain: lock until today's reading bonus is paid",
    )


def run_evening(paths: Paths, *, production: bool, today: date | None = None) -> int:
    """Lock until the reading rung is paid; 0 paid, 10 ended, 3 no display."""
    if _ledger.key_usable(paths.key_file):
        auto_grant(paths, today=today)  # a day that asks nothing pays itself
    else:
        _logger.error("integrity key %s unreadable -- rung unchecked", paths.key_file)
    if reading_paid(paths, today):
        _logger.info("not locking: the reading rung is paid today")
        return 0
    if production and not wait_for_x_server(timeout_s=X_WAIT_S):
        _logger.error("no X server within %.0f s -- evening gate not shown", X_WAIT_S)
        return EXIT_NO_X
    snap = snapshot(paths, today=today)
    write_next_file(paths, snap)
    _logger.warning("evening lock: the reading rung is unpaid")
    gate = EveningLock(paths, snap, production=production, today=today)
    gate.run()
    return gate.exit_code
