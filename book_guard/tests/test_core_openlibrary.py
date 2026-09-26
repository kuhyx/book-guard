# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_openlibrary with a fake ``urlopen``: no request ever leaves the machine."""

from __future__ import annotations

from email.message import Message
import io
import json
from typing import TYPE_CHECKING, Self
from urllib.error import HTTPError, URLError

import pytest

from book_guard import _openlibrary
from book_guard._openlibrary import BookInfo

if TYPE_CHECKING:
    from urllib.request import Request


class _Response:
    def __init__(self, payload: object) -> None:
        self.body = json.dumps(payload).encode()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_exc: object) -> None:
        return None

    def read(self) -> bytes:
        return self.body


class FakeOpen:
    """Maps a URL path (or its prefix before ``?``) to a payload or error."""

    def __init__(self, routes: dict[str, object]) -> None:
        self.routes = routes
        self.requests: list[Request] = []

    def __call__(self, request: Request, *, timeout: int) -> _Response:
        assert timeout == 15
        self.requests.append(request)
        path = request.full_url.removeprefix("https://openlibrary.org")
        answer = self.routes[path.split("?")[0]]
        if isinstance(answer, BaseException):
            raise answer
        return _Response(answer)


def _install(monkeypatch: pytest.MonkeyPatch, routes: dict[str, object]) -> FakeOpen:
    fake = FakeOpen(routes)
    monkeypatch.setattr(_openlibrary, "urlopen", fake)
    return fake


def _http(code: int) -> HTTPError:
    return HTTPError("https://openlibrary.org/x", code, "err", Message(), io.BytesIO())


def test_lookup_isbn_with_author(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = _install(
        monkeypatch,
        {
            "/isbn/9780000000002.json": {
                "title": "Solaris",
                "number_of_pages": 204,
                "authors": [{"key": "/authors/OL1A"}],
            },
            "/authors/OL1A.json": {"name": "Stanisław Lem"},
        },
    )
    info = _openlibrary.lookup_isbn("9780000000002")
    assert info == BookInfo("Solaris", "Stanisław Lem", 204, "9780000000002")
    assert fake.requests[0].get_header("User-agent", "").startswith("book-guard")


@pytest.mark.parametrize(
    ("doc", "routes", "author", "pages"),
    [
        ({"number_of_pages": 0}, {}, "", None),
        ({"number_of_pages": "12"}, {}, "", None),
        ({"authors": []}, {}, "", None),
        ({"authors": "Lem"}, {}, "", None),
        ({"authors": ["/authors/OL1A"]}, {}, "", None),
        ({"authors": [{"key": 5}]}, {}, "", None),
        ({"authors": [{"key": "/a/X"}]}, {"/a/X.json": _http(500)}, "", None),
        ({"authors": [{"key": "/a/X"}]}, {"/a/X.json": URLError("down")}, "", None),
        ({"authors": [{"key": "/a/X"}]}, {"/a/X.json": ["list"]}, "", None),
        ({"authors": [{"key": "/a/X"}]}, {"/a/X.json": {}}, "", None),
    ],
)
def test_lookup_isbn_partial_docs(
    monkeypatch: pytest.MonkeyPatch,
    doc: dict[str, object],
    routes: dict[str, object],
    author: str,
    pages: int | None,
) -> None:
    _install(monkeypatch, {"/isbn/1.json": doc, **routes})
    info = _openlibrary.lookup_isbn("1")
    assert info == BookInfo("", author, pages, "1")


def test_lookup_isbn_author_json_error(monkeypatch: pytest.MonkeyPatch) -> None:
    doc = {"title": "T", "authors": [{"key": "/a/Y"}]}
    fake = _install(monkeypatch, {"/isbn/1.json": doc, "/a/Y.json": None})

    def bad_json(request: Request, *, timeout: int) -> _Response:
        response = fake(request, timeout=timeout)
        if request.full_url.endswith("/a/Y.json"):
            response.body = b"<html>"
        return response

    monkeypatch.setattr(_openlibrary, "urlopen", bad_json)
    assert _openlibrary.lookup_isbn("1") == BookInfo("T", "", None, "1")


def test_lookup_isbn_not_found(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, {"/isbn/404.json": _http(404)})
    assert _openlibrary.lookup_isbn("404") is None


@pytest.mark.parametrize(
    ("error", "match"), [(_http(503), "503"), (URLError("offline"), "offline")]
)
def test_lookup_isbn_failure_raises(
    monkeypatch: pytest.MonkeyPatch, error: OSError, match: str
) -> None:
    _install(monkeypatch, {"/isbn/1.json": error})
    with pytest.raises(OSError, match=match):
        _openlibrary.lookup_isbn("1")


def test_lookup_isbn_non_dict(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, {"/isbn/1.json": ["not", "a", "doc"]})
    assert _openlibrary.lookup_isbn("1") is None


def test_lookup_isbn_quotes_path(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = _install(monkeypatch, {"/isbn/a%20b.json": _http(404)})
    assert _openlibrary.lookup_isbn("a b") is None
    assert fake.requests[0].full_url.endswith("/isbn/a%20b.json")


def test_search_title(monkeypatch: pytest.MonkeyPatch) -> None:
    docs = [
        {
            "title": "Solaris",
            "author_name": ["Lem", "Other"],
            "number_of_pages_median": 204,
            "isbn": ["0123456789", "9780000000002", "9781111111111"],
        },
        "junk row",
        {"title": "No ISBN-13", "author_name": [], "isbn": ["0123456789"]},
        {"title": "Empty", "isbn": [], "number_of_pages_median": -3},
        {"title": "Bad", "author_name": "Lem", "isbn": "978"},
    ]
    fake = _install(monkeypatch, {"/search.json": {"docs": docs}})
    hits = _openlibrary.search_title("Solaris & more", limit=3)
    assert hits == [
        BookInfo("Solaris", "Lem", 204, "9780000000002"),
        BookInfo("No ISBN-13", "", None, "0123456789"),
        BookInfo("Empty", "", None, None),
        BookInfo("Bad", "", None, None),
    ]
    url = fake.requests[0].full_url
    assert "title=Solaris+%26+more" in url
    assert "limit=3" in url


@pytest.mark.parametrize("payload", [["list"], {"docs": "nope"}, {}])
def test_search_title_odd_payloads(
    monkeypatch: pytest.MonkeyPatch, payload: object
) -> None:
    _install(monkeypatch, {"/search.json": payload})
    assert _openlibrary.search_title("x") == []


def test_search_title_failure_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, {"/search.json": URLError("offline")})
    with pytest.raises(OSError, match="offline"):
        _openlibrary.search_title("x")
