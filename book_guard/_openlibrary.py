# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Book metadata from Open Library: by ISBN, or a title search to find one.

Stdlib ``urllib`` only -- two GET endpoints do not justify a dependency.
"""

from __future__ import annotations

from dataclasses import dataclass
from http import HTTPStatus
import json
import logging
from typing import Final
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

_logger: Final = logging.getLogger(__name__)
_ISBN13_LEN: Final = 13
_TIMEOUT: Final = 15
_HEADERS: Final = {"User-Agent": "book-guard/1.0 (github.com/kuhyx/book-guard)"}


@dataclass(frozen=True)
class BookInfo:
    """What Open Library knows about one edition (or one work, for search)."""

    title: str
    author: str
    pages: int | None
    isbn: str | None


def _get(path: str) -> object:
    """GET a JSON document. Raises ``OSError``/``ValueError`` on failure."""
    try:
        with urlopen(
            Request(f"https://openlibrary.org{path}", headers=_HEADERS),
            timeout=_TIMEOUT,
        ) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        # An HTTPError holds the error response open; close it before the
        # caller decides what the status means.
        exc.close()
        raise


def _author_of_edition(doc: dict[str, object]) -> str:
    """The first author's name, or "" -- editions only carry author keys."""
    authors = doc.get("authors")
    if not isinstance(authors, list) or not authors or not isinstance(authors[0], dict):
        return ""
    key = authors[0].get("key")
    if not isinstance(key, str):
        return ""
    try:
        author = _get(f"{key}.json")
    except (OSError, ValueError) as exc:
        _logger.warning("author lookup %s failed (%s); leaving it blank", key, exc)
        return ""
    return str(author.get("name", "")) if isinstance(author, dict) else ""


def lookup_isbn(isbn: str) -> BookInfo | None:
    """The edition with this ISBN, or ``None`` if Open Library lacks it.

    Raises:
        OSError: The network or the service failed -- not "no such book".
    """
    try:
        doc = _get(f"/isbn/{quote(isbn)}.json")
    except OSError as exc:
        if getattr(exc, "code", None) == HTTPStatus.NOT_FOUND:
            return None
        raise
    if not isinstance(doc, dict):
        return None
    pages = doc.get("number_of_pages")
    return BookInfo(
        title=str(doc.get("title", "")),
        author=_author_of_edition(doc),
        pages=pages if isinstance(pages, int) and pages > 0 else None,
        isbn=isbn,
    )


def _best_isbn(values: object) -> str | None:
    """Prefer an ISBN-13 from a search hit's list; fall back to any."""
    if not isinstance(values, list):
        return None
    isbns = [str(v) for v in values]
    thirteen = [v for v in isbns if len(v) == _ISBN13_LEN]
    candidates = thirteen or isbns
    return candidates[0] if candidates else None


def search_title(title: str, *, limit: int = 8) -> list[BookInfo]:
    """Books matching a title, most relevant first.

    Raises:
        OSError: The network or the service failed.
    """
    fields = "title,author_name,number_of_pages_median,isbn"
    query = urlencode({"title": title, "fields": fields, "limit": str(limit)})
    doc = _get(f"/search.json?{query}")
    rows = doc.get("docs") if isinstance(doc, dict) else None
    hits: list[BookInfo] = []
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        authors = row.get("author_name")
        pages = row.get("number_of_pages_median")
        hits.append(
            BookInfo(
                title=str(row.get("title", "")),
                author=str(authors[0]) if isinstance(authors, list) and authors else "",
                pages=pages if isinstance(pages, int) and pages > 0 else None,
                isbn=_best_isbn(row.get("isbn")),
            )
        )
    return hits
