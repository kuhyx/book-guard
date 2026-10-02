# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Book metadata by ISBN from the sources besides Open Library.

* Biblioteka Narodowa (``data.bn.org.pl``): the Polish national
  bibliography; legal deposit makes it complete for Polish books, and its
  MARC 300 field carries the printed page count.
* e-ISBN (``e-isbn.pl``): what Polish publishers registered, ONIX 3.0.
* Google Books: anonymous calls share one worldwide quota and are often
  refused; an API key in ``Paths.google_key_file`` gives them their own.

Each returns a ``BookInfo`` or ``None`` (the source answered: no such book)
and raises :class:`~book_guard._http.UnavailableError` when it did not answer.
"""

from __future__ import annotations

import json
import re
from typing import Final
from urllib.parse import urlencode

from book_guard import _http
from book_guard._openlibrary import BookInfo

_ISBN13_LEN: Final = 13
_ROMAN_TEN: Final = 10
"""An ISBN-10 check digit of ten is written X."""
_BRACKETS: Final = re.compile(r"\[[^\]]*\]")
_PAGE_COUNT: Final = re.compile(r"(\d+)\s*,?\s*(?:s\.|s\b|str|stron|p\.|pages)")
_ONIX_FIELD: Final = r"<{0}>([^<]*)</{0}>"


def isbn10_of(isbn: str) -> str | None:
    """The ISBN-10 form of a 978- ISBN-13 (older records only carry that)."""
    if len(isbn) != _ISBN13_LEN or not isbn.startswith("978"):
        return None
    core = isbn[3:12]
    check = sum((10 - i) * int(d) for i, d in enumerate(core)) % 11
    digit = (11 - check) % 11
    return core + ("X" if digit == _ROMAN_TEN else str(digit))


def pages_of_extent(extent: str) -> int | None:
    """The printed page count in a MARC 300 $a.

    ``406, [2] strony`` -> 406; ``2 t. w 1 wol. (615 s.)`` -> 615. Bracketed
    (unnumbered) pages never count: the last *numbered* page is what a page
    photo can show.
    """
    match = _PAGE_COUNT.search(_BRACKETS.sub("", extent))
    return int(match.group(1)) if match else None


def _strip(text: str) -> str:
    return text.strip().rstrip(" :/;,.").strip()


def _first_last(name: str) -> str:
    """``Sheridan, Michael`` -> ``Michael Sheridan``."""
    last, _, first = _strip(name).partition(", ")
    return f"{first} {last}" if first else last


def _marc(bib: dict[str, object]) -> dict[str, dict[str, str]]:
    """MARC tag -> its subfields (first occurrence of each code)."""
    fields: dict[str, dict[str, str]] = {}
    marc = bib.get("marc")
    for field in marc.get("fields", []) if isinstance(marc, dict) else []:
        for tag, value in field.items() if isinstance(field, dict) else []:
            if tag in fields or not isinstance(value, dict):
                continue
            subs: dict[str, str] = {}
            for sub in value.get("subfields", []):
                for code, text in sub.items() if isinstance(sub, dict) else []:
                    subs.setdefault(code, str(text))
            fields[tag] = subs
    return fields


def _bn_record(bib: dict[str, object], isbn: str) -> BookInfo:
    marc = _marc(bib)
    title = _strip(marc.get("245", {}).get("a", ""))
    subtitle = _strip(marc.get("245", {}).get("b", ""))
    return BookInfo(
        title=f"{title}: {subtitle}" if subtitle else title,
        author=_first_last(marc.get("100", {}).get("a", "")),
        pages=pages_of_extent(marc.get("300", {}).get("a", "")),
        isbn=isbn,
    )


def biblioteka_narodowa(isbn: str) -> BookInfo | None:
    """The national bibliography's record for ``isbn`` (either form)."""
    for form in filter(None, (isbn, isbn10_of(isbn))):
        query = urlencode({"isbnIssn": form, "limit": "5"})
        body = _http.get("data.bn.org.pl", f"/api/institutions/bibs.json?{query}")
        doc = json.loads(body) if body else {}
        for bib in doc.get("bibs", []) if isinstance(doc, dict) else []:
            if isinstance(bib, dict) and form in str(bib.get("isbnIssn", "")).split():
                return _bn_record(bib, isbn)
    return None


def _onix(xml: str, tag: str) -> str:
    match = re.search(_ONIX_FIELD.format(tag), xml)
    return match.group(1).strip() if match else ""


def e_isbn(isbn: str) -> BookInfo | None:
    """What the publisher registered with e-ISBN (no product: ``None``)."""
    body = _http.get("e-isbn.pl", f"/IsbnWeb/api.xml?{urlencode({'isbn': isbn})}")
    xml = body.decode("utf-8") if body else ""
    if "<Product" not in xml:
        return None
    title, subtitle = _onix(xml, "TitleText"), _onix(xml, "Subtitle")
    pages = _onix(xml, "ExtentValue") if _onix(xml, "ExtentUnit") == "03" else ""
    return BookInfo(
        title=f"{title}: {subtitle}" if subtitle else title,
        author=_first_last(_onix(xml, "PersonNameInverted"))
        or _onix(xml, "PersonName"),
        pages=int(pages) if pages.isdigit() and int(pages) > 0 else None,
        isbn=isbn,
    )


def google_books(isbn: str, key: str = "") -> BookInfo | None:
    """Google Books' first volume for ``isbn``."""
    params = {"q": f"isbn:{isbn}"} | ({"key": key} if key else {})
    body = _http.get("www.googleapis.com", f"/books/v1/volumes?{urlencode(params)}")
    doc = json.loads(body) if body else {}
    items = doc.get("items") if isinstance(doc, dict) else None
    if not isinstance(items, list) or not items or not isinstance(items[0], dict):
        return None
    volume = items[0].get("volumeInfo", {})
    authors = volume.get("authors") or [""]
    pages = volume.get("pageCount")
    title, subtitle = str(volume.get("title", "")), str(volume.get("subtitle", ""))
    return BookInfo(
        title=f"{title}: {subtitle}" if subtitle else title,
        author=str(authors[0]),
        pages=pages if isinstance(pages, int) and pages > 0 else None,
        isbn=isbn,
    )
