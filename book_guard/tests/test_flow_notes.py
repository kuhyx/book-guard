# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The reader's notes (_notes) and the full-summary store (_summaries)."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _notes, _summaries
from book_guard._app_handlers import HANDLERS
from book_guard._errors import CorruptFileError
from book_guard._requests import handle_requests
from book_guard.tests._flow_helpers import (
    ISBN13,
    add_book,
)
from book_guard.tests._library_helpers import note

if TYPE_CHECKING:
    from book_guard._paths import Paths

Out = pytest.CaptureFixture[str]


# -- notes ---------------------------------------------------------------------


def test_note_upsert_update_and_stale_edit(bg_paths: Paths) -> None:
    add_book(bg_paths)
    assert note(bg_paths) == (True, "Note saved.")
    assert note(bg_paths, text="A shark.", updated_at="2026-10-06T10:00:00Z") == (
        True,
        "Note updated.",
    )
    assert note(bg_paths, text="old", updated_at="2026-10-01T00:00:00Z") == (
        True,
        "A newer edit of this note is already saved.",
    )
    assert note(bg_paths, text="A shark.", updated_at="2026-10-07T00:00:00Z")[0]
    (saved,) = _notes.load(bg_paths).values()
    assert saved["text"] == "A shark."
    assert saved["chapter"] == "One"
    assert saved["created_at"] == "2026-10-05T10:00:00+00:00"
    assert [p["text"] for p in saved["previous"]] == ["A marlin."]


@pytest.mark.parametrize(
    ("fields", "problem"),
    [
        ({"note_id": "short"}, "needs an id"),
        ({"text": "   "}, "cannot be empty"),
        ({"text": 5}, "cannot be empty"),
        ({"text": "x" * (_notes.MAX_NOTE_CHARS + 1)}, "at most"),
        ({"isbn": "123"}, "No registered book"),
    ],
)
def test_note_refusals(
    bg_paths: Paths, fields: dict[str, object], problem: str
) -> None:
    add_book(bg_paths)
    ok, message = note(bg_paths, **fields)
    assert not ok
    assert problem in message


@pytest.mark.parametrize(
    ("raw", "page"),
    [(12, 12), ("7", 7), ("0", None), (True, None), (3.5, None), ("x", None)],
)
def test_note_pages(raw: object, page: int | None) -> None:
    assert _notes._page(raw) == page


def test_note_bad_time_is_now(caplog: pytest.LogCaptureFixture) -> None:
    assert _notes._when("yesterday").endswith("+00:00")
    assert "is not ISO" in caplog.text


def test_notes_by_page_then_time() -> None:
    notes: dict[str, dict[str, Any]] = {
        "a": {"isbn": "1", "page": None, "created_at": "1"},
        "b": {"isbn": "1", "page": 9, "created_at": "2"},
        "c": {"isbn": "1", "page": 2, "created_at": "3"},
        "d": {"isbn": "2", "page": 1, "created_at": "4"},
    }
    assert [n["created_at"] for n in _notes.of_book(notes, "1")] == ["3", "2", "1"]


def test_corrupt_notes_file_is_never_overwritten(bg_paths: Paths) -> None:
    add_book(bg_paths)
    bg_paths.notes.parent.mkdir(parents=True, exist_ok=True)
    bg_paths.notes.write_text('["x"]', encoding="utf-8")
    with pytest.raises(CorruptFileError):
        _notes.load(bg_paths)
    bg_paths.requests.mkdir(parents=True)
    request = {"id": "request01", "type": "note", "note_id": "note0001"}
    request |= {"isbn": ISBN13, "text": "kept?"}
    (bg_paths.requests / "request01.json").write_text(
        json.dumps(request), encoding="utf-8"
    )
    assert handle_requests(bg_paths, HANDLERS) == 1
    answer = json.loads(
        (bg_paths.responses / "request01.json").read_text(encoding="utf-8")
    )
    assert not answer["ok"]
    assert bg_paths.notes.read_text(encoding="utf-8") == '["x"]'


def test_notes_skip_non_dict_rows(bg_paths: Paths) -> None:
    bg_paths.notes.parent.mkdir(parents=True, exist_ok=True)
    bg_paths.notes.write_text('{"a": 1, "b": {"isbn": "1"}}', encoding="utf-8")
    assert _notes.load(bg_paths) == {"b": {"isbn": "1"}}


# -- full summaries ------------------------------------------------------------


def test_summaries_unreadable_or_odd_files_are_empty(bg_paths: Paths) -> None:
    assert _summaries.load(bg_paths) == {}
    bg_paths.summaries.parent.mkdir(parents=True)
    for text in ("{", "[1]"):
        bg_paths.summaries.write_text(text, encoding="utf-8")
        assert _summaries.load(bg_paths) == {}
    bg_paths.summaries.write_text('{"a": "x", "b": 2}', encoding="utf-8")
    assert _summaries.load(bg_paths) == {"a": "x"}


def test_summary_save_failure_is_logged(
    bg_paths: Paths, caplog: pytest.LogCaptureFixture
) -> None:
    bg_paths.summaries.mkdir(parents=True)  # a directory where the file goes
    _summaries.save_unlocked(bg_paths, "session:x", "text")
    assert "could not keep the full summary" in caplog.text
