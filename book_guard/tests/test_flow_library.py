# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The library document, its text, and ``book-guard library``."""

from __future__ import annotations

from datetime import timedelta
import json
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _cli, _library, _library_text
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import (
    ISBN13,
    T0,
    add_book,
    quiz_pair,
    seed_photos,
)
from book_guard.tests._library_helpers import LONG, OTHER, grade, note

if TYPE_CHECKING:
    from book_guard._paths import Paths

Out = pytest.CaptureFixture[str]


# -- the document --------------------------------------------------------------


def test_library_end_to_end(bg_paths: Paths, monkeypatch: pytest.MonkeyPatch) -> None:
    add_book(bg_paths, pages=11)
    sid = grade(bg_paths, monkeypatch)
    note(bg_paths)
    doc = json.loads(bg_paths.library_file.read_text(encoding="utf-8"))
    (book,) = doc["books"]
    assert (book["status"], book["current"], book["pages_read"]) == (
        "finished",
        True,
        1,
    )
    (session,) = book["sessions"]
    assert session["id"] == sid
    assert session["status"] == "credited"
    assert [p["role"] for p in session["photos"]] == ["start", "end"]
    (attempt,) = session["attempts"]
    assert attempt["summary"] == LONG.strip()  # in full, not the ledger's cut
    assert (attempt["passed"], attempt["graded"], attempt["missing"]) == (
        True,
        True,
        [],
    )
    # The photos left the cache: the session still shows, from the ledger row.
    seed_photos(bg_paths)
    (book,) = _library.build(bg_paths, snapshot(bg_paths))["books"]
    (session,) = book["sessions"]
    assert session["photos"] == []
    assert (session["start_page"], session["end_page"]) == (10, 11)
    assert session["ended_at"].startswith("2026-10-")
    assert book["notes"][0]["text"] == "A marlin."


def test_books_unread_failed_waiting_and_order(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    add_book(bg_paths)  # older sessions fall to the first registered book
    add_book(bg_paths, isbn=OTHER, pages=None)  # never read
    add_book(bg_paths)  # current again
    grade(bg_paths, monkeypatch, passed=False)
    seed_photos(bg_paths, *quiz_pair("wait", T0 + timedelta(days=9)))
    doc = _library.build(bg_paths, snapshot(bg_paths))
    current, unread = doc["books"]
    assert current["isbn"] == ISBN13
    assert (unread["status"], unread["first_read_at"], unread["last_page_read"]) == (
        "not-started",
        None,
        None,
    )
    statuses = sorted(s["status"] for s in current["sessions"])
    assert statuses == ["failed-quiz", "needs-quiz"]
    assert current["status"] == "reading"
    waiting = next(s for s in current["sessions"] if s["status"] == "needs-quiz")
    assert (waiting["isbn"], waiting["attempts"]) == (ISBN13, [])


def test_session_from_a_row_with_odd_numbers(bg_paths: Paths) -> None:
    assert _library._iso("") == ""
    assert _library._int("x") is None
    assert _library._numbers({"pages": "7"}, None)["pages"] == 7


def test_unreadable_notes_show_none(bg_paths: Paths) -> None:
    add_book(bg_paths)
    bg_paths.notes.parent.mkdir(parents=True, exist_ok=True)
    bg_paths.notes.write_text("[]", encoding="utf-8")
    (book,) = _library.build(bg_paths, snapshot(bg_paths))["books"]
    assert book["notes"] == []


def test_write_library_skips_unchanged_and_logs_failures(
    bg_paths: Paths, caplog: pytest.LogCaptureFixture
) -> None:
    add_book(bg_paths)
    snap = snapshot(bg_paths)
    _library.write_library(bg_paths, snap)
    stamp = bg_paths.library_file.stat().st_mtime_ns
    _library.write_library(bg_paths, snap)
    assert bg_paths.library_file.stat().st_mtime_ns == stamp
    bg_paths.library_file.write_text("{", encoding="utf-8")
    _library.write_library(bg_paths, snap)
    assert "could not write" in caplog.text


# -- text -----------------------------------------------------------------------


def _doc() -> dict[str, Any]:
    attempt = {
        "id": "session:a#2",
        "passed": False,
        "summary": "",
        "feedback": "",
        "grader": "",
        "graded": False,
    }
    session = {
        "ended_at": "2026-10-05T10:00:00+00:00",
        "start_page": 1,
        "end_page": 9,
        "pages": 8,
        "minutes": 20,
        "status": "failed-quiz",
        "attempts": [attempt],
    }
    book = {
        "isbn": "1",
        "title": "T",
        "author": "",
        "pages": None,
        "status": "reading",
        "current": False,
        "last_page_read": None,
        "pages_read": 0,
        "finished_at": None,
        "first_read_at": None,
        "last_read_at": None,
        "chapters": [{"start": 3, "title": "Two"}],
        "sessions": [session, {**session, "attempts": []}],
        "notes": [{"text": "n", "updated_at": None}],
    }
    return {"books": [book]}


def test_library_text_branches() -> None:
    doc = _doc()
    (book,) = doc["books"]
    lines = _library_text.book_detail(book)
    assert (
        lines[0]
        == "1  T  [in progress] p. 0/?, 0 pages credited; read - .. -; 2 sessions, 1 notes"
    )
    assert "  p. 3: Two" in lines
    assert "    2. failed (ungraded)" in lines
    assert "      summary: -" in lines
    assert lines[-1] == "  -: n"
    md = _library_text.markdown(doc)
    assert "### Chapters\n\n- p. 3: Two\n" in md
    assert "_no summary_\n\n> Grader (-): \n" in md
    assert md.endswith("2026-10-05  p. 1-9 (8 p, 20 min) failed-quiz\n")
    bare = {**book, "chapters": [], "notes": [], "sessions": []}
    assert _library_text.markdown({"books": [bare]}).endswith("finished -\n")


# -- book-guard library --------------------------------------------------------


def test_cli_library(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, capsys: Out
) -> None:
    assert _cli.main(["library"]) == 0
    assert capsys.readouterr().out == "No books registered yet.\n"
    add_book(bg_paths, pages=11)
    grade(bg_paths, monkeypatch)
    note(bg_paths)
    assert _cli.main(["library"]) == 0
    assert capsys.readouterr().out.startswith(f"* {ISBN13}  War -- Tol  [finished]")
    assert _cli.main(["library", "--isbn", "978-0-14-044913-6"]) == 0
    detail = capsys.readouterr().out
    assert "Sessions:" in detail
    assert "1. passed (claude:haiku)" in detail or "1. passed (" in detail
    assert "(p. 5, One): A marlin." in detail
    assert _cli.main(["library", "--export", "md"]) == 0
    assert capsys.readouterr().out.startswith("# Reading library\n\n## War -- Tol")
    assert _cli.main(["library", "--isbn", "123"]) == 1
    assert "No registered book has ISBN 123." in capsys.readouterr().err
