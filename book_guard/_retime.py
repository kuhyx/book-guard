# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The app's ``session_times`` request: narrow one ungraded session.

Rules and storage live in :mod:`book_guard._session_times`; this is the
validating writer, kept apart because it needs the full snapshot.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from book_guard._atomic_json import write_json
from book_guard._constants import MIN_SECONDS_PER_PAGE
from book_guard._flock import exclusive
from book_guard._requests import Response
from book_guard._session_times import load_times, when
from book_guard._state import snapshot

if TYPE_CHECKING:
    from datetime import datetime

    from book_guard._paths import Paths


def _hhmm(moment: datetime) -> str:
    return moment.astimezone().strftime("%H:%M")


def set_times(paths: Paths, request: dict[str, Any]) -> Response:
    """The app's ``session_times`` request: narrow one session's times."""
    sid = str(request.get("session_id", ""))
    start, end = when(request.get("start")), when(request.get("end"))
    with exclusive(paths):
        view = next(
            (v for v in snapshot(paths).sessions if v.session.session_id == sid), None
        )
        if view is None:
            return Response(ok=False, message="No such session.")
        session = view.session
        if view.status in {"credited", "failed"}:
            return Response(ok=False, message="This session was already graded.")
        first, last = session.start.taken, session.end.taken
        start = start or session.started_at
        end = end or session.ended_at
        if not first <= start < end <= last:
            return Response(
                ok=False,
                message=(
                    f"Times must stay within the photos: {_hhmm(first)}-"
                    f"{_hhmm(last)}, start before end."
                ),
            )
        needed = session.pages * MIN_SECONDS_PER_PAGE
        if (end - start).total_seconds() < needed:
            return Response(
                ok=False,
                message=(
                    f"{session.pages} pages need at least {needed // 60} minutes."
                ),
            )
        times = load_times(paths.session_times)
        times[sid] = (start if start > first else None, end if end < last else None)
        write_json(
            paths.session_times,
            {
                key: {
                    "start": s.isoformat() if s else "",
                    "end": e.isoformat() if e else "",
                }
                for key, (s, e) in times.items()
            },
            indent=1,
        )
    minutes = int((end - start).total_seconds() // 60)
    return Response(
        ok=True,
        message=(
            f"p. {session.start.page}-{session.end.page}: "
            f"{_hhmm(start)}-{_hhmm(end)} ({minutes} min)"
        ),
    )
