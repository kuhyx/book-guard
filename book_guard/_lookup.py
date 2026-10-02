# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""ISBN -> book metadata from every source there is, cached and paced.

Order: a Polish ISBN (978-83 / 83) asks Biblioteka Narodowa first, then
Open Library; anything else the other way round; then e-ISBN, then Google
Books. Fields merge across sources -- the first title, the first author,
the first page count -- and the walk stops once title, author and page
count are all known. Title + page count is what makes a cached answer final:
the length of the book is what the pace needs.

Rarely, and politely: a lookup that found title and pages is cached for
good, anything less is re-asked after :data:`RECHECK` (a book is registered
about once a fortnight, so the services see a handful of requests a month).
Each source is asked at most once per :data:`MIN_GAP`, and a source that
refuses (429, 5xx, timeout) is left alone for an hour, doubling up to a day.
Only answers are cached, never a refusal. These two small files are not
value-carrying state, so they are written atomically but outside the
ledger lock -- a lookup can take a minute and must not hold that lock.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
import json
import logging
import time
from typing import TYPE_CHECKING, Final

from book_guard._atomic_json import write_json
from book_guard._http import UnavailableError
from book_guard._openlibrary import BookInfo, lookup_isbn
from book_guard._sources import biblioteka_narodowa, e_isbn, google_books

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

RECHECK: Final = timedelta(days=14)
MIN_GAP: Final = 2.0
BACKOFF_FIRST: Final = 3600.0
BACKOFF_MAX: Final = 86400.0
_ISBN10_LEN: Final = 10


def _google(paths: Paths, isbn: str) -> BookInfo | None:
    key_file = paths.google_key_file
    key = key_file.read_text(encoding="utf-8").strip() if key_file.is_file() else ""
    return google_books(isbn, key)


FETCHERS: Final[dict[str, Callable[[Paths, str], BookInfo | None]]] = {
    "biblioteka-narodowa": lambda _paths, isbn: biblioteka_narodowa(isbn),
    "openlibrary": lambda _paths, isbn: lookup_isbn(isbn),
    "e-isbn": lambda _paths, isbn: e_isbn(isbn),
    "google-books": _google,
}


def source_order(isbn: str) -> list[str]:
    """Which sources to ask, best first, for this ISBN."""
    polish = isbn.startswith("97883") or (
        len(isbn) == _ISBN10_LEN and isbn.startswith("83")
    )
    first = ["biblioteka-narodowa", "openlibrary"]
    return (first if polish else first[::-1]) + ["e-isbn", "google-books"]


def _load(path: Path) -> dict[str, dict[str, object]]:
    if not path.exists():
        return {}
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _logger.warning("unreadable %s (%s); starting it afresh", path.name, exc)
        return {}
    return doc if isinstance(doc, dict) else {}


def _num(entry: dict[str, object], key: str) -> float:
    value = entry.get(key)
    return float(value) if isinstance(value, int | float) else 0.0


def _complete(info: BookInfo | None) -> bool:
    return bool(info and info.title and info.pages)


def _merge(have: BookInfo | None, new: BookInfo) -> BookInfo:
    if have is None:
        return new
    return BookInfo(
        title=have.title or new.title,
        author=have.author or new.author,
        pages=have.pages or new.pages,
        isbn=have.isbn,
    )


def _cached(paths: Paths, isbn: str, now: datetime) -> tuple[bool, BookInfo | None]:
    """(usable, info) from the cache."""
    entry = _load(paths.isbn_cache).get(isbn)
    if not isinstance(entry, dict):
        return False, None
    pages = entry.get("pages")
    info = BookInfo(
        title=str(entry.get("title", "")),
        author=str(entry.get("author", "")),
        pages=pages if isinstance(pages, int) else None,
        isbn=isbn,
    )
    info_or_none = info if info.title or info.pages else None
    checked = datetime.fromisoformat(
        str(entry.get("checked_at", "1970-01-01T00:00:00+00:00"))
    )
    usable = _complete(info_or_none) or now - checked < RECHECK
    return usable, info_or_none if usable else None


def _store(paths: Paths, isbn: str, info: BookInfo | None, now: datetime) -> None:
    cache = _load(paths.isbn_cache)
    cache[isbn] = {
        "title": info.title if info else "",
        "author": info.author if info else "",
        "pages": info.pages if info else None,
        "checked_at": now.isoformat(),
    }
    write_json(paths.isbn_cache, cache, indent=1)


def _ask(
    paths: Paths,
    name: str,
    isbn: str,
    clock: Callable[[], float],
    sleep: Callable[[float], None],
) -> BookInfo | None:
    """One paced request to one source; a refusal starts or doubles its backoff."""
    state = _load(paths.lookup_sources)
    mine = state.get(name, {})
    now = clock()
    retry_after = _num(mine, "retry_after")
    if now < retry_after:
        msg = f"{name} is backing off for another {retry_after - now:.0f} s"
        raise UnavailableError(msg)
    wait = MIN_GAP - (now - _num(mine, "last"))
    if wait > 0:
        sleep(wait)
    try:
        result = FETCHERS[name](paths, isbn)
    except (OSError, ValueError) as exc:
        backoff = min(max(2 * _num(mine, "backoff"), BACKOFF_FIRST), BACKOFF_MAX)
        state[name] = {
            "last": clock(),
            "retry_after": clock() + backoff,
            "backoff": backoff,
        }
        write_json(paths.lookup_sources, state, indent=1)
        msg = f"{name}: {exc}"
        raise UnavailableError(msg) from exc
    state[name] = {"last": clock(), "retry_after": 0.0, "backoff": 0.0}
    write_json(paths.lookup_sources, state, indent=1)
    return result


def lookup_book(
    paths: Paths,
    isbn: str,
    *,
    now: datetime | None = None,
    clock: Callable[[], float] = time.time,
    sleep: Callable[[float], None] = time.sleep,
) -> BookInfo | None:
    """Everything the sources know about ``isbn``; ``None`` if none has it.

    Raises:
        UnavailableError: No source answered at all -- not "no such book".
    """
    moment = now or datetime.now(tz=UTC)
    usable, info = _cached(paths, isbn, moment)
    if usable:
        return info
    found: BookInfo | None = None
    asked = refused = 0
    for name in source_order(isbn):
        if _complete(found) and found and found.author:
            break
        asked += 1
        try:
            result = _ask(paths, name, isbn, clock, sleep)
        except UnavailableError as exc:
            _logger.warning("ISBN %s: %s", isbn, exc)
            refused += 1
            continue
        if result is not None:
            found = _merge(found, result)
    if refused == asked:
        msg = "no book source answered"
        raise UnavailableError(msg)
    if _complete(found) or not refused:
        _store(paths, isbn, found, moment)
    return found
