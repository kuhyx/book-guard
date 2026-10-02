# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The snapshot, its JSON twin, its text rendering and publishing both."""

from __future__ import annotations

from datetime import date, timedelta
import json
import logging
from typing import TYPE_CHECKING

from book_guard import _publish
from book_guard._bookindex import index_path
from book_guard._ledger import CREDIT, REJECT
from book_guard._sessions import NEEDS_CHECK, NEEDS_QUIZ
from book_guard._state import CREDITED, FAILED, awaiting_check, awaiting_quiz, snapshot
from book_guard._state_json import SCHEMA, to_json
from book_guard.tests._flow_helpers import (
    ISBN13,
    LOCKED_DAY,
    T0,
    add_book,
    add_credit,
    add_entry,
    add_escape,
    check_pair,
    only_session,
    quiz_pair,
    rec,
    seed_photos,
)

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths


def _seed_three_sessions(paths: Paths) -> list[str]:
    """A credited, a failed and a check-waiting session, plus an open start."""
    credited = quiz_pair("a", T0)
    failed = quiz_pair("b", T0 + timedelta(hours=1))
    waiting = check_pair("c", T0 + timedelta(hours=2))
    lone = rec("lone", 50, T0 + timedelta(hours=3))
    seed_photos(paths, *credited, *failed, *waiting, lone)
    ids = [only_session(p).session_id for p in (credited, failed, waiting)]
    add_entry(paths, ids[0], CREDIT, "2026-10-05", 1)
    add_entry(paths, ids[1], REJECT, "2026-10-05")
    return ids


def test_before_the_gate_starts(bg_paths: Paths) -> None:
    snap = snapshot(bg_paths, today=date(2026, 9, 20))
    assert (snap.locked, snap.reason) == (False, "book-guard starts on 2026-10-01")
    assert snap.book is None
    assert snap.open_start is None


def test_free_day(bg_paths: Paths) -> None:
    snap = snapshot(bg_paths, today=LOCKED_DAY, is_free=lambda d: d == LOCKED_DAY)
    assert (snap.locked, snap.reason, snap.free_today) == (
        False,
        "today is a free day",
        True,
    )


def test_escaped_today(bg_paths: Paths) -> None:
    add_escape(bg_paths, LOCKED_DAY.isoformat())
    add_escape(bg_paths, "2026-09-30")  # another month: not counted
    snap = snapshot(bg_paths, today=LOCKED_DAY)
    assert snap.reason == "today's lock was skipped with the escape hatch"
    assert (snap.locked, snap.escaped_today, snap.escapes_left) == (False, True, 1)


def test_behind_locks(bg_paths: Paths) -> None:
    snap = snapshot(bg_paths, today=LOCKED_DAY)
    assert (snap.locked, snap.reason) == (True, "440 pages behind the pace line")
    assert snap.escapes_left == 2


def test_on_pace(bg_paths: Paths) -> None:
    add_credit(bg_paths, "2026-10-03", 500)
    snap = snapshot(bg_paths, today=LOCKED_DAY)
    assert (snap.locked, snap.reason) == (False, "on pace")


def test_escapes_left_never_negative(bg_paths: Paths) -> None:
    for day in ("2026-10-01", "2026-10-02", "2026-10-03"):
        add_escape(bg_paths, day)
    assert snapshot(bg_paths, today=LOCKED_DAY).escapes_left == 0


def test_session_views_take_ledger_verdicts(bg_paths: Paths) -> None:
    ids = _seed_three_sessions(bg_paths)
    snap = snapshot(bg_paths, today=LOCKED_DAY)
    assert [v.status for v in snap.sessions] == [CREDITED, FAILED, NEEDS_CHECK]
    assert [v.session.session_id for v in snap.sessions] == ids
    assert awaiting_check(snap) == [snap.sessions[2]]
    assert awaiting_quiz(snap) == []
    assert snap.open_start is not None
    assert snap.open_start.page == 50


def test_to_json_full(bg_paths: Paths) -> None:
    _seed_three_sessions(bg_paths)
    add_book(bg_paths)
    index_path(bg_paths, ISBN13).parent.mkdir(parents=True)
    index_path(bg_paths, ISBN13).touch()
    snap = snapshot(bg_paths, today=LOCKED_DAY)
    doc = to_json(bg_paths, snap)
    assert doc["schema"] == SCHEMA
    assert doc["today"] == "2026-10-15"
    assert doc["book"] == {
        "isbn": ISBN13,
        "title": "War",
        "author": "Tol",
        "pages": 300,
        "has_file": True,
    }
    assert doc["pace"]["month"] == "2026-10"
    assert doc["pace"]["behind"] == 439
    assert doc["open_start"]["page"] == 50
    first = doc["sessions"][0]
    assert (first["status"], first["book"], first["check_page"]) == (
        CREDITED,
        "War",
        None,
    )
    assert doc["todo"][0].startswith("TAKE A PHOTO of page ")
    json.dumps(doc)


def test_to_json_empty(bg_paths: Paths) -> None:
    seed_photos(bg_paths, *quiz_pair())
    doc = to_json(bg_paths, snapshot(bg_paths, today=LOCKED_DAY))
    assert doc["book"] is None
    assert doc["open_start"] is None
    assert doc["sessions"][0]["book"] == ""
    assert doc["sessions"][0]["status"] == NEEDS_QUIZ


def test_publish_writes_both_files(bg_paths: Paths) -> None:
    snap = snapshot(bg_paths, today=LOCKED_DAY)
    _publish.write_next_file(bg_paths, snap)
    body = bg_paths.next_file.read_text(encoding="utf-8")
    assert body.startswith("book-guard -- open this after uploading photos.\n\n")
    assert "LOCKED: 440 pages behind the pace line" in body
    assert body.endswith("Page numbers must be visible.\n")
    state = json.loads(bg_paths.state_file.read_text(encoding="utf-8"))
    assert state["locked"] is True


def test_publish_failure_is_logged_not_raised(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    def full(*_args: object) -> None:
        msg = "disk full"
        raise OSError(msg)

    monkeypatch.setattr(_publish, "write_text", full)
    with caplog.at_level(logging.WARNING):
        _publish.write_next_file(bg_paths, snapshot(bg_paths, today=LOCKED_DAY))
    assert "disk full" in caplog.text
    assert not bg_paths.state_file.exists()
