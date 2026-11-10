# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The app's request/response side channel and its three handlers."""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _app_handlers, _grading
from book_guard._app_handlers import HANDLERS
from book_guard._claude import ClaudeUnavailableError
from book_guard._http import UnavailableError
from book_guard._openlibrary import BookInfo
from book_guard._requests import Response, handle_requests
from book_guard.tests._flow_helpers import ISBN13

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
    assert _answer(bg_paths) == {"id": RID, "ok": False, "code": "unknown_type"}
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
    assert _answer(bg_paths) == {"id": RID, "ok": False, "code": "error"}


def test_passed_flag_is_forwarded(bg_paths: Paths) -> None:
    _put(bg_paths, f"{RID}.json", {"id": RID, "type": "x"})
    handle_requests(
        bg_paths, {"x": lambda _p, _r: Response(True, "failed", passed=False)}
    )
    assert _answer(bg_paths) == {
        "id": RID,
        "ok": True,
        "code": "failed",
        "passed": False,
    }


# -- handlers ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "expected"),
    [(True, None), (None, None), ([3], None), ("0", None), (" 12 ", 12), (7, 7)],
)
def test_positive_int(raw: object, expected: int | None) -> None:
    assert _app_handlers._positive_int(raw) == expected


def test_register_rejects_a_bad_isbn(bg_paths: Paths) -> None:
    response = HANDLERS["register"](bg_paths, {"isbn": "12-34"})
    assert response == Response(ok=False, code="bad_isbn")


def test_register_through_open_library(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.INFO)
    seen: list[str] = []

    def lookup(_paths: Paths, isbn: str) -> BookInfo:
        seen.append(isbn)
        return BookInfo(title="War", author="Tol", pages=900, isbn=isbn)

    monkeypatch.setattr(_grading, "lookup_book", lookup)
    response = HANDLERS["register"](
        bg_paths, {"isbn": "978-0-14-044913-6", "pages": "1225"}
    )
    assert response == Response(True, "registered", data={"known": True})
    assert seen == [ISBN13]
    assert "Now reading: War -- Tol, last page 1225" in caplog.text


def test_register_says_when_no_catalogue_knows_it(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    # The app's cue to offer a title search for the typed ISBN.
    monkeypatch.setattr(_grading, "lookup_book", lambda _paths, _isbn: None)
    response = HANDLERS["register"](bg_paths, {"isbn": ISBN13})
    assert response.ok
    assert response.data == {"known": False}


def test_register_offline_is_not_ok(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    def offline(_paths: Paths, _isbn: str) -> BookInfo:
        msg = "no route"
        raise UnavailableError(msg)

    monkeypatch.setattr(_grading, "lookup_book", offline)
    response = HANDLERS["register"](bg_paths, {"isbn": ISBN13})
    assert response == Response(ok=False, code="offline")
    assert not bg_paths.ledger.exists()


def test_response_data_reaches_the_app(bg_paths: Paths) -> None:
    _put(bg_paths, f"{RID}.json", {"id": RID, "type": "x"})

    def with_data(_paths: Paths, _req: dict[str, Any]) -> Response:
        return Response(ok=True, code="found", data={"title": "War"})

    assert handle_requests(bg_paths, {"x": with_data}) == 1
    assert _answer(bg_paths) == {
        "id": RID,
        "ok": True,
        "code": "found",
        "data": {"title": "War"},
    }
