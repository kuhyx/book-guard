# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The in-app reader's files: each book's page map and text, kept fresh.

The PC builds the current book's page map (:mod:`book_guard._ebook_map`)
from its photographed pages and serves two files to the app over dufs:

* ``Reading/ebooks/<isbn>.txt`` -- the indexed ebook text, exactly the text
  the grader slices (astral characters as U+FFFD, so the app's UTF-16
  offsets are the PC's offsets);
* ``Reading/ebooks/<isbn>.map.json`` -- the knots, the story's bounds, the
  text's sha256 and size.

The app downloads both once and reads offline. The PC never reads the
served copy back (the share is writable by the phone's login): credit is
computed from the private copy under ``data_dir/ebook_maps/``.

:func:`refresh` runs after the photo pass has published its state (the map
takes ~0.1 s on a 1 MB book, and nothing at all when no input changed) and
after a book file is indexed.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
import hashlib
import json
import logging
from typing import TYPE_CHECKING, Any, Final

from book_guard import _ledger, _photos
from book_guard._anchor import MIN_ANCHOR_CHARS
from book_guard._atomic_json import write_json, write_text
from book_guard._bookindex import index_path, load
from book_guard._books import book_at, current
from book_guard._ebook_map import PageMap, build_map
from book_guard._ebook_text import served_text

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._ledger import Ledger
    from book_guard._paths import Paths
    from book_guard._photos import PhotoRecord

_logger: Final = logging.getLogger(__name__)


@dataclass(frozen=True)
class EbookMap:
    """A book's page map with the text it was built on."""

    isbn: str
    pages: PageMap
    text_sha: str
    """sha256 of the served text: a session read on another text is refused."""
    chars: int
    photos: int
    generated_at: str
    inputs: str
    """What it was built from; an unchanged fingerprint skips the rebuild."""


def map_file(paths: Paths, isbn: str) -> Path:
    """The private map the PC credits from."""
    return paths.ebook_maps / f"{isbn}.json"


def _served(paths: Paths, isbn: str) -> tuple[Path, Path]:
    """The app's copies: (text, map)."""
    return paths.ebooks / f"{isbn}.txt", paths.ebooks / f"{isbn}.map.json"


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def _photographed(
    ledger: Ledger, records: list[PhotoRecord], isbn: str
) -> list[PhotoRecord]:
    """Accepted page photos of ``isbn`` with enough text to locate."""
    return [
        r
        for r in records
        if r.page
        and len(r.text.strip()) >= MIN_ANCHOR_CHARS
        and (book := book_at(ledger, r.taken)) is not None
        and book.isbn == isbn
    ]


def load_map(paths: Paths, isbn: str) -> EbookMap | None:
    """``isbn``'s page map, or None when there is none (or it is unreadable)."""
    path = map_file(paths, isbn)
    if not path.exists():
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        pages = PageMap.from_json(raw)
        if pages is None:
            return None
        return EbookMap(
            isbn=isbn,
            pages=pages,
            text_sha=str(raw["text_sha"]),
            chars=int(raw["chars"]),
            photos=pages.photos,
            generated_at=str(raw["generated_at"]),
            inputs=str(raw["inputs"]),
        )
    except (OSError, ValueError, KeyError, TypeError) as exc:
        _logger.warning("unreadable page map %s (%s): no in-app reading", path, exc)
        return None


def refresh(paths: Paths) -> bool:
    """Rebuild and serve the current book's map if its inputs changed.

    Inputs: the index file (a re-attached ebook), the copy's last page and
    the set of photographed pages. Returns whether anything was written.
    """
    ledger = _ledger.load(paths.ledger, paths.key_file)
    book = current(ledger)
    index_file = index_path(paths, book.isbn) if book else None
    if book is None or index_file is None or not index_file.exists():
        return False
    photos = _photographed(
        ledger, _photos.usable_pages(_photos.load(paths.photos)), book.isbn
    )
    stat = index_file.stat()
    inputs = _sha(
        json.dumps(
            [
                stat.st_size,
                stat.st_mtime_ns,
                book.pages,
                sorted(f"{p.sha}:{p.page}" for p in photos),
            ]
        )
    )
    text_file, served_map = _served(paths, book.isbn)
    old = load_map(paths, book.isbn)
    if old and old.inputs == inputs and text_file.exists() and served_map.exists():
        return False
    index = load(paths, book.isbn)
    text = served_text(index.text if index else "")
    page_map = build_map(text, [(int(p.page or 0), p.text) for p in photos], book.pages)
    if page_map is None:
        _logger.info(
            "%s: %d photographed pages do not locate in order in the ebook yet;"
            " no in-app reading",
            book.isbn,
            len(photos),
        )
        return False
    sha = _sha(text)
    doc: dict[str, Any] = {
        **page_map.to_json(),
        "isbn": book.isbn,
        "text": f"ebooks/{text_file.name}",
        "text_sha": sha,
        "chars": len(text),
        "estimated": True,
        "generated_at": datetime.now(tz=UTC).isoformat(),
        "inputs": inputs,
    }
    if old is None or old.text_sha != sha or not text_file.exists():
        write_text(text_file, text)
    write_json(map_file(paths, book.isbn), doc, indent=1)
    write_json(served_map, doc, indent=1)
    _logger.info("%s: page map from %d pages", book.isbn, page_map.photos)
    return True


def state_info(paths: Paths, isbn: str) -> dict[str, Any] | None:
    """What ``state.json`` tells the app about the in-app reader, or None."""
    found = load_map(paths, isbn)
    if found is None:
        return None
    text_file, served_map = _served(paths, isbn)
    return {
        "map": f"ebooks/{served_map.name}",
        "text": f"ebooks/{text_file.name}",
        "text_sha": found.text_sha,
        "chars": found.chars,
        "photos": found.photos,
        "generated_at": found.generated_at,
    }
