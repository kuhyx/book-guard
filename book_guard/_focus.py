# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Focus-project stand-down: a declared project switches this gate off.

``focus_project.stands_down("book", day)`` is True while an active focus
project replaces reading. The day is then treated exactly like a sick day that
does not keep ``book``: 0 pages asked, no lock, counted as kept.

Fail closed: if ``focus_project`` cannot be imported the gate behaves as it did
before the package existed (NOT standing down) and the error is logged, once
per process. The module is looked up at call time, never from-imported, so the
suite can replace ``stands_down`` on it.
"""

from __future__ import annotations

from datetime import date, timedelta
import importlib
import logging
from typing import TYPE_CHECKING, Final

if TYPE_CHECKING:
    from types import ModuleType

GENERIC_NAME: Final = "focus project"

GATE: Final = "book"
"""The gate name ``focus_project`` knows this gate by."""

_logger = logging.getLogger(__name__)
_warned: set[str] = set()
"""Which failures were already logged: one line per process, not per day."""


def _module() -> ModuleType | None:
    """The ``focus_project`` package, or None (logged once) when not importable."""
    try:
        return importlib.import_module("focus_project")
    except ImportError:
        if "import" not in _warned:
            _warned.add("import")
            _logger.exception(
                "focus_project is not importable: not standing down for a "
                "focus project (the gate applies as before)"
            )
        return None


def stands_down(gate: str, day: date) -> bool:
    """Whether an active focus project replaces ``gate`` on ``day``."""
    module = _module()
    return module is not None and bool(module.stands_down(gate, day))


def project_name(day: date) -> str:
    """The name of the focus project active on ``day`` (for status text).

    Only asked on a day :func:`stands_down` already said yes to; a package
    that cannot say falls back to a generic name rather than hiding the day.
    """
    module = _module()
    project = None if module is None else module.active(day)
    return GENERIC_NAME if project is None else str(project.name)


def days_around(centre: date, radius: int) -> frozenset[date]:
    """The days within ``radius`` of ``centre`` on which this gate stands down.

    The pace maths takes a finite set of days, so a project's date range is
    sampled over the window the month's plan and yesterday's check can reach.
    """
    window = (centre + timedelta(days=n) for n in range(-radius, radius + 1))
    return frozenset(day for day in window if stands_down(GATE, day))
