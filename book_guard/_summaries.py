# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Every summary in full, outside the signed ledger.

A verdict row keeps ``summary[:1000]`` (the ledger is shared with the
consumers and must stay small); the library shows what was really written.
Keyed by the verdict's entry id, so each rewrite (``<session>#2``, ...)
keeps its own text. Not value-carrying, so unsigned, and never pruned.
Rows from before this file existed fall back to the ledger's copy -- no
summary written before it reached 1000 characters, so nothing was cut.
"""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING, Final

from book_guard._atomic_json import write_json

if TYPE_CHECKING:
    from book_guard._ledger import Entry
    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)


def _read(paths: Paths) -> dict[str, str] | None:
    """The kept summaries; ``{}`` when none yet, ``None`` when unreadable."""
    if not paths.summaries.exists():
        return {}
    try:
        raw = json.loads(paths.summaries.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _logger.warning("unreadable %s (%s)", paths.summaries, exc)
        return None
    if not isinstance(raw, dict):
        _logger.warning("%s is not a summaries file", paths.summaries)
        return None
    return {str(k): v for k, v in raw.items() if isinstance(v, str)}


def load(paths: Paths) -> dict[str, str]:
    """Verdict id -> full summary; missing or unreadable is empty."""
    return _read(paths) or {}


def save_unlocked(paths: Paths, entry_id: str, summary: str) -> None:
    """Record ``summary`` for ``entry_id``. The caller holds ``exclusive``.

    Never raises: the ledger row is the record, this is the long copy. An
    unreadable file is left alone rather than overwritten with one entry.
    """
    found = _read(paths)
    if found is None:
        _logger.warning("not keeping the full summary of %s", entry_id)
        return
    found[entry_id] = summary.strip()
    try:
        write_json(paths.summaries, found, indent=1)
    except OSError as exc:
        _logger.warning("could not keep the full summary of %s: %s", entry_id, exc)


def full_text(found: dict[str, str], entry: Entry) -> str:
    """``entry``'s summary in full, else the ledger's (possibly cut) copy."""
    return found.get(entry.entry_id) or entry.detail.get("summary", "")
