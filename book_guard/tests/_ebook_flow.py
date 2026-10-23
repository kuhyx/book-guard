# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The in-app reading flow tests' book, photos and request builder."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
import hashlib
from typing import TYPE_CHECKING, Any

from book_guard import (
    _ebook,
    _embed,
)
from book_guard._app_handlers import HANDLERS
from book_guard._ebook_text import served_text
from book_guard.tests._ebook_helpers import TEXT, middle, ocr
from book_guard.tests._flow_helpers import ISBN13, T0, add_book, rec, seed_photos

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._photos import PhotoRecord

PHOTO_PAGES = (9, 30, 51, 77, 100)
NOW = datetime.now(UTC).replace(microsecond=0)
SUMMARY = "They walked to the river and argued about the money. " * 4


def book_photos() -> list[PhotoRecord]:
    """One photo a day: no two pair into a photo session."""
    return [
        rec(f"p{page}", page, T0 + timedelta(days=i), text=ocr(page))
        for i, page in enumerate(PHOTO_PAGES)
    ]


def map_book(bg_paths: Paths) -> Paths:
    """A registered book with its ebook indexed, five pages photographed."""
    add_book(bg_paths, pages=120)
    _embed.build(bg_paths, ISBN13, TEXT, source="book.epub")
    seed_photos(bg_paths, *book_photos())
    assert _ebook.refresh(bg_paths)
    return bg_paths


def text_sha(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def ebook_request(**over: object) -> dict[str, Any]:
    body: dict[str, Any] = {
        "id": "req0000001",
        "type": "ebook_session",
        "session": "abcdef0123456789",
        "isbn": ISBN13,
        "start_offset": middle(40),
        "end_offset": middle(52),
        "started_at": (NOW - timedelta(hours=2)).isoformat(),
        "ended_at": (NOW - timedelta(hours=1)).isoformat(),
        "text_sha": text_sha(served_text(TEXT)),
    }
    return body | over


def send_session(paths: Paths, **over: object) -> Any:
    return HANDLERS["ebook_session"](paths, ebook_request(**over))
