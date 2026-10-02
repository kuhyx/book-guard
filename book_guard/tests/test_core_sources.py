# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_sources against recorded response shapes; ``_http.get`` is faked."""

from __future__ import annotations

import json

import pytest

from book_guard import _http, _sources
from book_guard._http import UnavailableError
from book_guard._openlibrary import BookInfo

ISBN = "9788368380002"


def _routes(
    monkeypatch: pytest.MonkeyPatch, routes: dict[str, bytes | None]
) -> list[str]:
    seen: list[str] = []

    def get(host: str, path: str) -> bytes | None:
        url = f"{host}{path}"
        seen.append(url)
        for fragment, body in routes.items():
            if fragment in url:
                return body
        return None

    monkeypatch.setattr(_http, "get", get)
    return seen


def _bib(isbn: str, *, extent: str = "406, [2] strony :") -> dict[str, object]:
    return {
        "isbnIssn": f"{isbn} 83",
        "marc": {
            "fields": [
                {"001": "b1"},
                {"020": {"subfields": [{"a": isbn}]}},
                {"100": {"subfields": [{"a": "Sheridan, Michael"}, {"d": "(1957- )"}]}},
                {
                    "245": {
                        "subfields": [{"a": "Czerwony cesarz :"}, {"b": "Xi i Chiny /"}]
                    }
                },
                {"245": {"subfields": [{"a": "ignored second 245"}]}},
                {"300": {"subfields": [{"a": extent}, "junk"]}},
                "junk",
            ]
        },
    }


def test_isbn10_of() -> None:
    assert _sources.isbn10_of("9780306406157") == "0306406152"
    assert _sources.isbn10_of("9780804429573") == "080442957X"
    assert _sources.isbn10_of("9790000000001") is None
    assert _sources.isbn10_of("0306406152") is None


@pytest.mark.parametrize(
    ("extent", "pages"),
    [
        ("406, [2] strony, [8] stron tablic :", 406),
        ("2 t. w 1 wol. (615 s.) :", 615),
        ("3 t. w 1 wol. (602, [2] s., [24] s. il. kolor.) ;", 602),
        ("702 s., 16 k. il. :", 702),
        ("XII, 350 s.", 350),
        ("[4], 280 s.", 280),
        ("x, 212 pages ;", 212),
        ("1 vol.", None),
        ("", None),
    ],
)
def test_pages_of_extent(extent: str, pages: int | None) -> None:
    assert _sources.pages_of_extent(extent) == pages


def test_biblioteka_narodowa(monkeypatch: pytest.MonkeyPatch) -> None:
    body = json.dumps({"bibs": ["junk", _bib("9999999999999"), _bib(ISBN)]})
    _routes(monkeypatch, {"bibs.json": body.encode()})
    assert _sources.biblioteka_narodowa(ISBN) == BookInfo(
        "Czerwony cesarz: Xi i Chiny", "Michael Sheridan", 406, ISBN
    )


def test_biblioteka_narodowa_falls_back_to_isbn10(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    old = json.dumps({"bibs": [_bib("0306406152", extent="")]}).encode()
    seen = _routes(
        monkeypatch, {"isbnIssn=9780306406157": b"{}", "isbnIssn=0306406152": old}
    )
    info = _sources.biblioteka_narodowa("9780306406157")
    assert info is not None
    assert (info.isbn, info.pages) == ("9780306406157", None)
    assert len(seen) == 2


def test_biblioteka_narodowa_odd_records(monkeypatch: pytest.MonkeyPatch) -> None:
    bare = {"isbnIssn": ISBN, "marc": "nope"}
    _routes(monkeypatch, {"bibs.json": json.dumps({"bibs": [bare]}).encode()})
    assert _sources.biblioteka_narodowa(ISBN) == BookInfo("", "", None, ISBN)
    _routes(monkeypatch, {"bibs.json": b"[]"})
    assert _sources.biblioteka_narodowa(ISBN) is None
    _routes(monkeypatch, {})
    assert _sources.biblioteka_narodowa(ISBN) is None


_ONIX = """<ONIXMessage><Product><TitleText>Czerwony cesarz</TitleText>
<Subtitle>Xi i Chiny</Subtitle>{person}{extent}</Product></ONIXMessage>"""


def test_e_isbn(monkeypatch: pytest.MonkeyPatch) -> None:
    xml = _ONIX.format(
        person="<PersonNameInverted>Sheridan, Michael</PersonNameInverted>",
        extent="<ExtentValue>406</ExtentValue><ExtentUnit>03</ExtentUnit>",
    )
    _routes(monkeypatch, {"e-isbn.pl": xml.encode()})
    assert _sources.e_isbn(ISBN) == BookInfo(
        "Czerwony cesarz: Xi i Chiny", "Michael Sheridan", 406, ISBN
    )


def test_e_isbn_partial_and_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    xml = _ONIX.format(
        person="<PersonName>Michael Sheridan</PersonName>",
        extent="<ExtentValue>12</ExtentValue><ExtentUnit>05</ExtentUnit>",
    )
    _routes(monkeypatch, {"e-isbn.pl": xml.encode()})
    info = _sources.e_isbn(ISBN)
    assert info is not None
    assert (info.author, info.pages) == ("Michael Sheridan", None)
    _routes(monkeypatch, {"e-isbn.pl": b"<ONIXMessage><Header/></ONIXMessage>"})
    assert _sources.e_isbn(ISBN) is None
    _routes(monkeypatch, {})
    assert _sources.e_isbn(ISBN) is None


def test_google_books(monkeypatch: pytest.MonkeyPatch) -> None:
    volume = {
        "title": "Red Emperor",
        "subtitle": "Xi",
        "authors": ["M. S."],
        "pageCount": 400,
    }
    seen = _routes(
        monkeypatch,
        {"googleapis": json.dumps({"items": [{"volumeInfo": volume}]}).encode()},
    )
    assert _sources.google_books(ISBN, "k3y") == BookInfo(
        "Red Emperor: Xi", "M. S.", 400, ISBN
    )
    assert "key=k3y" in seen[0]
    bare = {"items": [{"volumeInfo": {"title": "T", "pageCount": 0}}]}
    seen = _routes(monkeypatch, {"googleapis": json.dumps(bare).encode()})
    assert _sources.google_books(ISBN) == BookInfo("T", "", None, ISBN)
    assert "key=" not in seen[0]


@pytest.mark.parametrize(
    "body", [b'{"totalItems": 0}', b'{"items": ["x"]}', b"[]", None]
)
def test_google_books_no_volume(
    monkeypatch: pytest.MonkeyPatch, body: bytes | None
) -> None:
    _routes(monkeypatch, {"googleapis": body} if body else {})
    assert _sources.google_books(ISBN) is None


def test_refusals_propagate(monkeypatch: pytest.MonkeyPatch) -> None:
    def refuse(_host: str, _path: str) -> bytes:
        msg = "429"
        raise UnavailableError(msg)

    monkeypatch.setattr(_http, "get", refuse)
    with pytest.raises(UnavailableError):
        _sources.google_books(ISBN)
