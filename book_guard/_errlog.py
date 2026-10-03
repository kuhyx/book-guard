# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""One append-only log of everything that went wrong, phone and PC alike.

``Reading/logs/errors.jsonl``: one JSON object per line, newest last --

    {"at": "2026-10-03T12:27:52+02:00", "host": "pc", "stage": "claude",
     "error": "claude exited 1: Claude AI usage limit reached", ...}

Written for a later Claude session as much as for a human: grep a stage,
``jq`` a field, no journal digging. Until 2026-10-03 a failed call logged
only the CLI's (empty) stderr -- "claude exited 1:" -- and the reason, which
the CLI prints on stdout, was lost.

The phone cannot append over WebDAV, so it uploads one file per entry to
``Reading/logs/phone/``; :func:`merge_phone` folds them in on every pass.

``data/claude_down.json`` marks an ongoing Claude outage, so the app can say
"waiting for the grader (Claude unavailable since 12:27)" instead of a bare
timeout.
"""

from __future__ import annotations

from datetime import datetime
import json
import logging
from typing import TYPE_CHECKING, Final

from book_guard._atomic_json import write_json

if TYPE_CHECKING:
    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

PC: Final = "pc"
PHONE: Final = "phone"
_MAX_PHONE_ENTRY: Final = 64_000


def _append(paths: Paths, entry: dict[str, object]) -> None:
    paths.error_log.parent.mkdir(parents=True, exist_ok=True)
    with paths.error_log.open("a", encoding="utf-8") as log:
        log.write(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")


def log_error(paths: Paths, stage: str, error: str, **detail: object) -> None:
    """Append one PC-side failure; never raises (logging must not break a run)."""
    entry: dict[str, object] = {
        "at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "host": PC,
        "stage": stage,
        "error": error,
        **detail,
    }
    try:
        _append(paths, entry)
    except OSError as exc:
        _logger.warning("could not write %s (%s)", paths.error_log, exc)


def merge_phone(paths: Paths) -> int:
    """Fold the phone's uploaded entries into the log; returns how many."""
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
            _append(paths, {"host": PHONE, **entry})
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
        _append(
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


def claude_failed(paths: Paths, error: str) -> None:
    """Log one failed Claude call and mark the outage (first failure wins)."""
    log_error(paths, "claude", error)
    if paths.claude_down.exists():
        return
    since = datetime.now().astimezone().isoformat(timespec="seconds")
    try:
        write_json(paths.claude_down, {"since": since, "error": error})
    except OSError as exc:
        _logger.warning("could not mark the Claude outage (%s)", exc)


def claude_ok(paths: Paths) -> None:
    """A call went through: the outage, if any, is over."""
    paths.claude_down.unlink(missing_ok=True)


def claude_down_since(paths: Paths) -> str | None:
    """When the current Claude outage began, or ``None`` if there is none."""
    if not paths.claude_down.exists():
        return None
    try:
        raw = json.loads(paths.claude_down.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _logger.warning("unreadable %s (%s)", paths.claude_down, exc)
        return None
    since = raw.get("since") if isinstance(raw, dict) else None
    return since if isinstance(since, str) else None
