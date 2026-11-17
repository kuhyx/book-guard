# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Error and slow-wait reporting for book-guard (utils DOCS-app-errors.md).

``install`` runs once from the CLI entry point: uncaught, thread and Tk
callback errors, and a Tk loop frozen over 1 s, go to the app-errors spool,
from which the PC's ingest files a board ticket. Only the CLI installs it, so
tests that build a lock window never touch the real spool. (``_errors`` holds
book-guard's exception types; this module is the reporter.)
"""

from __future__ import annotations

from dataclasses import dataclass

from gatelock import error_report

APP = "book-guard"
REPO = "kuhyx/book-guard"


@dataclass
class _Slot:
    """Holds the process's reporter once installed."""

    reporter: error_report.Reporter | None = None


#: The installed reporter (``SLOT.reporter``); None until ``install``.
SLOT = _Slot()


def install() -> error_report.Reporter:
    """Hook this process's errors once; return the reporter."""
    rep = error_report.install(APP, REPO)
    SLOT.reporter = rep
    return rep
