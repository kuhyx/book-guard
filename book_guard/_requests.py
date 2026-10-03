# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The app's side channel: request files in, response files out, over WebDAV.

The Flutter app (phone and desktop) talks to this PC only through the dufs
share. It writes ``Reading/requests/<id>.json``; the next pass (the path unit
fires on the write) handles it and writes ``Reading/responses/<id>.json``,
which the app polls. Everything a request can do, the CLI can do too --
there is no action here that bypasses the grader or mints a credit.

Request types:

* ``register`` -- ``{"isbn": str, "pages": int | null}``
* ``set_pages`` -- ``{"pages": int}`` for the current book
* ``summary`` -- ``{"session_id": str, "summary": str}``
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import logging
import re
from typing import TYPE_CHECKING, Any, Final

from book_guard._atomic_json import write_json
from book_guard._claude import ClaudeUnavailableError
from book_guard._errlog import log_error

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

_ID: Final = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
"""Request ids become file names: nothing that could climb out of the dir."""


@dataclass(frozen=True)
class Response:
    """What the app reads back."""

    ok: bool
    message: str
    passed: bool | None = None
    data: dict[str, Any] | None = None


def _pending(requests_dir: Path) -> list[Path]:
    if not requests_dir.is_dir():
        return []
    return sorted(
        p for p in requests_dir.iterdir() if p.suffix == ".json" and p.is_file()
    )


def _load(path: Path) -> dict[str, Any] | None:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _logger.warning("unreadable request %s (%s)", path.name, exc)
        return None
    return raw if isinstance(raw, dict) else None


def handle_requests(
    paths: Paths, handlers: dict[str, Callable[[Paths, dict[str, Any]], Response]]
) -> int:
    """Answer every pending request; returns how many were answered.

    A request whose handler hits a Claude outage is left in place and retried
    next pass, exactly like an unreadable photo -- the app keeps polling.
    """
    answered = 0
    for path in _pending(paths.requests):
        request = _load(path)
        rid = str(request.get("id", "")) if request else ""
        if not request or not _ID.fullmatch(rid) or rid != path.stem:
            _logger.warning("dropping malformed request %s", path.name)
            path.unlink(missing_ok=True)
            continue
        handler = handlers.get(str(request.get("type", "")))
        try:
            response = (
                handler(paths, request)
                if handler
                else Response(
                    ok=False, message=f"unknown request type {request.get('type')!r}"
                )
            )
        except ClaudeUnavailableError as exc:
            _logger.warning("request %s deferred: %s", rid, exc)
            continue
        except (OSError, ValueError) as exc:
            _logger.warning("request %s failed: %s", rid, exc)
            log_error(paths, "request", str(exc), request=rid, type=request.get("type"))
            response = Response(ok=False, message=str(exc))
        payload = {"id": rid, "ok": response.ok, "message": response.message}
        if response.passed is not None:
            payload["passed"] = response.passed
        if response.data is not None:
            payload["data"] = response.data
        write_json(paths.responses / f"{rid}.json", payload, indent=1)
        path.unlink(missing_ok=True)
        answered += 1
    return answered
