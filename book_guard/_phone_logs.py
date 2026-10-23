# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What the app uploads for the PC's logs, folded in on every pass.

The phone cannot append over WebDAV, so it uploads one file per entry to
``Reading/logs/phone/``; :func:`merge_phone` folds them into
``errors.jsonl`` (:mod:`book_guard._errlog`). Entries marked
``"level": "event"`` are not failures but the steps of the app's photo
pipeline (camera opened, photo stored, queued, uploaded, app paused...),
one ``attempt`` id per photo: they go to ``Reading/logs/phone-events.jsonl``
so a photo that never arrived still leaves a trail (2026-10-23: a start
photo vanished without one). :func:`merge_reports` files the app's "this
should not have failed" reports.
"""

from __future__ import annotations

from datetime import datetime
import json
import logging
from typing import TYPE_CHECKING, Final

from book_guard._errlog import PHONE, append_entry

if TYPE_CHECKING:
    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

_MAX_PHONE_ENTRY: Final = 64_000


def merge_phone(paths: Paths) -> int:
    """Fold the phone's uploaded entries into the logs; returns how many."""
    folder = paths.phone_logs
    if not folder.is_dir():
        return 0
    merged = 0
    for path in sorted(folder.glob("*.json")):
        try:
            raw = path.read_text(encoding="utf-8")[:_MAX_PHONE_ENTRY]
            entry = json.loads(raw)
        except (OSError, ValueError) as exc:
            _logger.warning("dropping unreadable phone log %s (%s)", path.name, exc)
            path.unlink(missing_ok=True)
            continue
        if isinstance(entry, dict):
            append_entry(
                paths, {"host": PHONE, **entry}, events=entry.get("level") == "event"
            )
            merged += 1
        path.unlink(missing_ok=True)
    return merged


def merge_reports(paths: Paths) -> int:
    """File the app's "this should not have failed" reports; returns how many.

    Each is a JPEG plus a JSON note (sent after the JPEG, so a note means
    both are there). Both move out of the share into ``data/reports/`` --
    the start of a new ``scripts/page_truth.py`` row -- and the log gets a
    ``bug-report`` line pointing at them.
    """
    folder = paths.uploaded_reports
    if not folder.is_dir():
        return 0
    filed = 0
    paths.reports.mkdir(parents=True, exist_ok=True)
    for note in sorted(folder.glob("*.json")):
        try:
            detail = json.loads(note.read_text(encoding="utf-8")[:_MAX_PHONE_ENTRY])
        except (OSError, ValueError) as exc:
            _logger.warning("dropping unreadable report %s (%s)", note.name, exc)
            note.unlink(missing_ok=True)
            continue
        image = note.with_suffix(".jpg")
        if image.exists():
            image.replace(paths.reports / image.name)
        note.replace(paths.reports / note.name)
        fields = detail if isinstance(detail, dict) else {}
        append_entry(
            paths,
            {
                "host": PHONE,
                **fields,
                "at": datetime.now().astimezone().isoformat(timespec="seconds"),
                "stage": "bug-report",
                "error": str(fields.get("failure", "reported by the reader")),
                "report": str(paths.reports / note.name),
            },
        )
        filed += 1
    return filed
