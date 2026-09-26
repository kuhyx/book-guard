# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The app's request/response side channel and its three handlers."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _app_handlers, _grading, _ledger
from book_guard._app_handlers import HANDLERS
from book_guard._books import current
from book_guard._claude import ClaudeUnavailableError
from book_guard._openlibrary import BookInfo
from book_guard._quiz import Verdict
from book_guard._requests import Response, handle_requests
from book_guard.tests._flow_helpers import ISBN13, add_book, quiz_pair, seed_photos

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths

RID = "req-0001"


def _put(paths: Paths, name: str, body: object) -> Path:
    paths.requests.mkdir(parents=True, exist_ok=True)
    path = paths.requests / name
    path.write_text(body if isinstance(body, str) else json.dumps(body))
    return path


def _answer(paths: Paths, rid: str = RID) -> dict[str, Any]:
    doc: dict[str, Any] = json.loads((paths.responses / f"{rid}.json").read_text())
    return doc


def test_no_requests_dir(bg_paths: Paths) -> None:
    assert handle_requests(bg_paths, HANDLERS) == 0


@pytest.mark.parametrize(
    ("name", "body"),
    [
        ("bad-json1.json", "{not json"),
        ("listbody.json", "[1, 2]"),
        ("no-id-abc.json", {"type": "register"}),
        ("short.json", {"id": "short", "type": "register"}),
        ("mismatch1.json", {"id": "other-id-1", "type": "register"}),
    ],
)
def test_malformed_requests_are_dropped(
    bg_paths: Paths, name: str, body: object
) -> None:
    path = _put(bg_paths, name, body)
    assert handle_requests(bg_paths, HANDLERS) == 0
    assert not path.exists()
    assert not bg_paths.responses.exists()


def test_non_json_and_directories_are_ignored(bg_paths: Paths) -> None:
    keep = _put(bg_paths, "notes.txt", "hello")
    (bg_paths.requests / "folder0001.json").mkdir()
    assert handle_requests(bg_paths, HANDLERS) == 0
    assert keep.exists()


def test_unknown_type_answers_an_error(bg_paths: Paths) -> None:
    path = _put(bg_paths, f"{RID}.json", {"id": RID, "type": "launch"})
    assert handle_requests(bg_paths, HANDLERS) == 1
    assert _answer(bg_paths) == {
        "id": RID,
        "ok": False,
        "message": "unknown request type 'launch'",
    }
    assert not path.exists()


def test_claude_outage_defers_the_request(bg_paths: Paths) -> None:
    def down(_paths: Paths, _request: dict[str, Any]) -> Response:
        msg = "down"
        raise ClaudeUnavailableError(msg)

    path = _put(bg_paths, f"{RID}.json", {"id": RID, "type": "x"})
    assert handle_requests(bg_paths, {"x": down}) == 0
    assert path.exists()
    assert not (bg_paths.responses / f"{RID}.json").exists()


@pytest.mark.parametrize("error", [OSError("disk"), ValueError("bad")])
def test_handler_errors_become_error_responses(
    bg_paths: Paths, error: Exception
) -> None:
    def broken(_paths: Paths, _request: dict[str, Any]) -> Response:
        raise error

    _put(bg_paths, f"{RID}.json", {"id": RID, "type": "x"})
    assert handle_requests(bg_paths, {"x": broken}) == 1
    assert _answer(bg_paths) == {"id": RID, "ok": False, "message": str(error)}


def test_passed_flag_is_forwarded(bg_paths: Paths) -> None:
    _put(bg_paths, f"{RID}.json", {"id": RID, "type": "x"})
    handle_requests(bg_paths, {"x": lambda _p, _r: Response(True, "yes", passed=False)})
    assert _answer(bg_paths)["passed"] is False


# -- handlers ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "expected"),
    [(True, None), (None, None), ([3], None), ("0", None), (" 12 ", 12), (7, 7)],
)
def test_positive_int(raw: object, expected: int | None) -> None:
    assert _app_handlers._positive_int(raw) == expected


def test_register_rejects_a_bad_isbn(bg_paths: Paths) -> None:
    response = HANDLERS["register"](bg_paths, {"isbn": "12-34"})
    assert response == Response(ok=False, message="That is not a 10- or 13-digit ISBN.")


def test_register_through_open_library(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen: list[str] = []

    def lookup(isbn: str) -> BookInfo:
        seen.append(isbn)
        return BookInfo(title="War", author="Tol", pages=900, isbn=isbn)

    monkeypatch.setattr(_grading, "lookup_isbn", lookup)
    response = HANDLERS["register"](
        bg_paths, {"isbn": "978-0-14-044913-6", "pages": "1225"}
    )
    assert response == Response(True, "Now reading: War -- Tol, last page 1225")
    assert seen == [ISBN13]


def test_register_offline_is_not_ok(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    def offline(_isbn: str) -> BookInfo:
        msg = "no route"
        raise OSError(msg)

    monkeypatch.setattr(_grading, "lookup_isbn", offline)
    response = HANDLERS["register"](bg_paths, {"isbn": ISBN13})
    assert not response.ok
    assert response.message.startswith("Open Library unreachable")


def test_set_pages(bg_paths: Paths) -> None:
    assert HANDLERS["set_pages"](bg_paths, {"pages": -3}) == Response(
        ok=False, message="The last page must be a positive number."
    )
    assert HANDLERS["set_pages"](bg_paths, {"pages": 5}) == Response(
        ok=False, message="No book registered yet."
    )
    add_book(bg_paths, pages=None)
    assert HANDLERS["set_pages"](bg_paths, {"pages": 412}) == Response(
        ok=True, message="War -- Tol: last page 412"
    )
    book = current(_ledger.load(bg_paths.ledger, bg_paths.key_file))
    assert book is not None
    assert book.pages == 412


def test_summary_for_a_stale_session(bg_paths: Paths) -> None:
    response = HANDLERS["summary"](bg_paths, {"session_id": "session:gone"})
    assert response == Response(
        ok=False, message="That session is not waiting for a summary any more."
    )


def test_summary_grades_the_session(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    records = quiz_pair()
    seed_photos(bg_paths, *records)
    monkeypatch.setattr(
        _grading, "grade", lambda *_a, **_k: Verdict(passed=True, feedback="Good.")
    )
    sid = f"session:{records[0].sha[:16]}-{records[1].sha[:16]}"
    response = HANDLERS["summary"](bg_paths, {"session_id": sid, "summary": "text"})
    assert response == Response(ok=True, message="Good.", passed=True)
    assert _ledger.load(bg_paths.ledger, bg_paths.key_file).has(sid)
