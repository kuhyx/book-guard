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
timeout. It is gone the instant it stops being true: any grade that goes
through (Claude or the local model) deletes it, and a usage cap's named
reset time is kept as ``until``, past which every reader treats it as
absent. Nothing probes Claude to find out.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
import json
import logging
import re
from typing import TYPE_CHECKING, Final
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from book_guard._atomic_json import write_json

if TYPE_CHECKING:
    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

PC: Final = "pc"
PHONE: Final = "phone"
_MAX_PHONE_ENTRY: Final = 64_000
_RESETS: Final = re.compile(
    r"\bresets\s+(\d{1,2})(?::(\d{2}))?\s*([ap]m)?(?![\w:])"
    r"(?:\s*\(([A-Za-z_]+(?:/[A-Za-z0-9_+-]+)*)\))?",
    re.IGNORECASE,
)
_HALF_DAY: Final = 12
_HOUR: Final = 60


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


def reset_at(error: str, since: datetime) -> datetime | None:
    """When the CLI says the limit lifts ("resets 4:40pm (Europe/Warsaw)").

    The next such wall-clock time after ``since``, in the named zone (else
    ``since``'s own). Only a time right after "resets" counts -- a dated
    reset ("resets Oct 20, 4pm") or anything odd is ``None``: no expiry
    beats a wrong one.
    """
    found = _RESETS.search(error)
    if found is None:
        return None
    hour_text, minute_text, half, zone = found.groups()
    hour, minute = int(hour_text), int(minute_text or 0)
    if half:  # a 12-hour clock: 12am is midnight, 12pm noon
        if not 1 <= hour <= _HALF_DAY:
            return None
        hour = hour % _HALF_DAY + (_HALF_DAY if half.lower() == "pm" else 0)
    elif minute_text is None or hour >= 2 * _HALF_DAY:  # "resets 4" is no time
        return None
    if minute >= _HOUR:
        return None
    try:
        tz = ZoneInfo(zone) if zone else since.tzinfo
    except (ZoneInfoNotFoundError, ValueError, OSError) as exc:
        _logger.warning("no reset time: unknown zone %r (%s)", zone, exc)
        return None
    local = since.astimezone(tz)
    at = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    return at if at > local else at + timedelta(days=1)


@dataclass(frozen=True)
class Outage:
    """A Claude outage still in force: ISO ``since`` and, if known, ``until``."""

    since: str
    until: str | None = None


def _read_flag(paths: Paths) -> dict[str, object] | None:
    if not paths.claude_down.exists():
        return None
    try:
        raw = json.loads(paths.claude_down.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _logger.warning("unreadable %s (%s)", paths.claude_down, exc)
        return None
    return raw if isinstance(raw, dict) else None


def _until(flag: dict[str, object]) -> datetime | None:
    raw = flag.get("until")
    if not isinstance(raw, str):
        return None
    try:
        until = datetime.fromisoformat(raw)
    except ValueError as exc:
        _logger.warning("ignoring the outage's until %r (%s)", raw, exc)
        return None
    return until if until.tzinfo else None


def claude_outage(paths: Paths, now: datetime | None = None) -> Outage | None:
    """The outage in force at ``now``, or ``None``.

    Past its ``until`` the flag is over: removed here, plainly unlinked like
    :func:`claude_ok` (the file is outside ``_flock``; every write of it is
    atomic, and this may run inside a held ledger lock).
    """
    flag = _read_flag(paths)
    since = flag.get("since") if flag else None
    if flag is None or not isinstance(since, str):
        return None
    until = _until(flag)
    if until is not None and until <= (now or datetime.now(tz=UTC)):
        paths.claude_down.unlink(missing_ok=True)
        return None
    return Outage(since, None if until is None else str(flag["until"]))


def claude_failed(paths: Paths, error: str, *, now: datetime | None = None) -> None:
    """Log one failed Claude call and mark the outage.

    The first failure of a live outage keeps ``since``; a later one may only
    add the reset time it names. An expired flag is a new outage.
    """
    log_error(paths, "claude", error)
    at = now or datetime.now().astimezone()
    live = claude_outage(paths, at)
    if live is not None and live.until is not None:
        return
    since = live.since if live else at.isoformat(timespec="seconds")
    flag: dict[str, object] = {"since": since, "error": error}
    if (until := reset_at(error, at)) is not None:
        flag["until"] = until.isoformat(timespec="seconds")
    elif live is not None:
        return
    try:
        write_json(paths.claude_down, flag)
    except OSError as exc:
        _logger.warning("could not mark the Claude outage (%s)", exc)


def claude_ok(paths: Paths) -> None:
    """A grade went through (Claude, or the local model): the outage is over."""
    paths.claude_down.unlink(missing_ok=True)


def claude_down_since(paths: Paths, now: datetime | None = None) -> str | None:
    """When the outage in force began, or ``None`` if there is none."""
    outage = claude_outage(paths, now)
    return outage.since if outage else None
