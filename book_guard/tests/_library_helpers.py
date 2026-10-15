# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A graded session and a note through the real paths, for the library tests."""

from __future__ import annotations

from datetime import timedelta
from typing import TYPE_CHECKING, Final

from book_guard import _grading
from book_guard._app_handlers import HANDLERS
from book_guard._quiz import Verdict
from book_guard._state import SessionView, snapshot
from book_guard.tests._flow_helpers import (
    ISBN13,
    T0,
    only_session,
    quiz_pair,
    seed_photos,
)

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths

LONG: Final = "The old man fished alone. " * 60  # past the ledger's 1000 characters
OTHER: Final = "9780684801223"


def grade(
    bg_paths: Paths,
    monkeypatch: pytest.MonkeyPatch,
    *,
    passed: bool = True,
    tag: str = "q",
    summary: str = LONG,
) -> str:
    """Grade one fresh 10 -> 11 session; returns its id."""
    records = quiz_pair(tag, T0 + timedelta(days=len(tag)))
    seed_photos(bg_paths, *records)
    snap = snapshot(bg_paths)
    view = SessionView(only_session(records), snap.book, "needs-quiz")
    verdict = Verdict(passed=passed, feedback="Good." if passed else "Thin.")
    monkeypatch.setattr(_grading, "grade", lambda *_a, **_k: verdict)
    _grading.quiz_one(bg_paths, view, summary)
    return view.session.session_id


def note(paths: Paths, **fields: object) -> tuple[bool, str]:
    """Send one ``note`` request (defaults: p. 5, chapter One); (ok, message)."""
    request = {
        "note_id": "note0001",
        "isbn": ISBN13,
        "text": "  A marlin.  ",
        "page": 5,
        "chapter": " One ",
        "created_at": "2026-10-05T10:00:00",
        "updated_at": "2026-10-05T10:00:00+02:00",
        **fields,
    }
    found = HANDLERS["note"](paths, request)
    return found.ok, found.message
