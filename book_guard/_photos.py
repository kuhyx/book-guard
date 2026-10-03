# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The photo cache: what every uploaded photo was read as, keyed by content.

Not value-carrying, so unsigned: forging a cache row can at most invent a
session, and a session only counts once it passes the quiz, whose grader sees
the transcribed pages. Keyed by SHA-256 so a photo uploaded twice is read once.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, fields
from datetime import datetime
import json
import logging
from typing import TYPE_CHECKING, Final

from book_guard._atomic_json import write_json
from book_guard._errors import CorruptFileError

if TYPE_CHECKING:
    from pathlib import Path

OK = "ok"
REJECTED = "rejected"


_logger: Final = logging.getLogger(__name__)


@dataclass(frozen=True)
class PhotoRecord:
    """One photo, as read.

    Attributes:
        sha: Content hash.
        name: Original file name, for the human.
        taken_at: EXIF capture time (ISO, aware), or "" when absent.
        uploaded_at: When it landed in the inbox (file mtime, ISO).
        kind: ``page`` / ``isbn`` / ``other``.
        page: Printed page number, pages only.
        isbn: Normalised ISBN, barcodes only.
        text: Transcribed body text -- the quiz's evidence.
        status: ``ok`` or ``rejected``.
        reason: Why it was rejected.
    """

    sha: str
    name: str
    taken_at: str
    uploaded_at: str
    kind: str
    page: int | None = None
    isbn: str | None = None
    text: str = ""
    status: str = OK
    reason: str = ""

    @property
    def taken(self) -> datetime:
        """``taken_at`` parsed; only meaningful for ``ok`` records."""
        return datetime.fromisoformat(self.taken_at)


def load(path: Path) -> dict[str, PhotoRecord]:
    """Every cached record. A missing file is an empty cache.

    Raises:
        ValueError: The file exists but is not a photo cache.
    """
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        _logger.warning("no photo cache at %s yet; starting empty", path)
        return {}
    if not isinstance(raw, dict):
        msg = f"{path} is not a photo cache"
        raise CorruptFileError(msg)
    # Fields a newer or older writer added are ignored (e.g. "rotation",
    # written for a few hours on 2026-10-03): a cache row must always load.
    known = {f.name for f in fields(PhotoRecord)}
    return {
        sha: PhotoRecord(**{k: v for k, v in row.items() if k in known})
        for sha, row in raw.items()
    }


def save(path: Path, records: dict[str, PhotoRecord]) -> None:
    """Atomically replace the cache."""
    write_json(path, {sha: asdict(r) for sha, r in records.items()}, indent=1)


def usable_pages(records: dict[str, PhotoRecord]) -> list[PhotoRecord]:
    """Accepted page photos, in capture order -- the session builder's input."""
    pages = [r for r in records.values() if r.status == OK and r.kind == "page"]
    return sorted(pages, key=lambda r: (r.taken, r.sha))
