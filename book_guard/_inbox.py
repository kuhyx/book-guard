# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Read new photos from the upload inbox into the photo cache.

Run by the ``.path`` unit the moment dufs-cloud writes a file, and by a
15-minute timer as the fallback. Idempotent: a photo already in the cache is
just filed away.

Three outcomes per file, and only the first two move it out of the inbox:

* **read** -- cached as a page / ISBN / other, or as rejected with a reason
  (no capture time, uploaded too late);
* **duplicate** -- same bytes as a cached photo;
* **not yet** -- still settling, undecodable (half-uploaded) or Claude was
  unreachable. Left where it is, nothing recorded, retried next trigger.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
import logging
import time
from typing import TYPE_CHECKING, Final

from book_guard import _photos
from book_guard._claude import ClaudeUnavailableError
from book_guard._constants import MAX_UPLOAD_DELAY, UPLOAD_SETTLE_SECONDS
from book_guard._photo import open_photo
from book_guard._photos import REJECTED, PhotoRecord
from book_guard._vision import ISBN, read_photo

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

    from book_guard._paths import Paths
    from book_guard._photo import PhotoFile
    from book_guard._vision import Reading

_logger: Final = logging.getLogger(__name__)

_SUFFIXES: Final = {".jpg", ".jpeg", ".png", ".webp"}


@dataclass
class InboxResult:
    """What one pass did, for the log and the CLI."""

    read: list[PhotoRecord] = field(default_factory=list)
    duplicates: int = 0
    deferred: list[str] = field(default_factory=list)
    new_isbns: list[str] = field(default_factory=list)


def _candidates(inbox: Path, now: float) -> list[Path]:
    """Image files old enough to have finished uploading, oldest first."""
    if not inbox.is_dir():
        return []
    stamped: list[tuple[float, Path]] = []
    for path in inbox.iterdir():
        try:
            mtime = path.stat().st_mtime
        except FileNotFoundError:
            _logger.warning(
                "%s vanished while listing (another pass took it)", path.name
            )
            continue
        settled = now - mtime >= UPLOAD_SETTLE_SECONDS
        if path.is_file() and path.suffix.lower() in _SUFFIXES and settled:
            stamped.append((mtime, path))
    return [path for _, path in sorted(stamped)]


def _file_away(path: Path, processed: Path, sha: str) -> None:
    processed.mkdir(parents=True, exist_ok=True)
    path.replace(processed / f"{sha[:12]}-{path.name}")


def _rejected(
    photo: PhotoFile, path: Path, uploaded: datetime, reason: str
) -> PhotoRecord:
    taken = photo.taken_at.isoformat() if photo.taken_at else ""
    return PhotoRecord(
        sha=photo.sha,
        name=path.name,
        taken_at=taken,
        uploaded_at=uploaded.isoformat(),
        kind="other",
        status=REJECTED,
        reason=reason,
    )


def _record(
    photo: PhotoFile, path: Path, uploaded: datetime, reader: Callable[[str], Reading]
) -> PhotoRecord:
    """Classify one photo. Raises ``ClaudeUnavailableError`` from ``reader``."""
    if photo.taken_at is None:
        return _rejected(photo, path, uploaded, "no EXIF capture time")
    if uploaded - photo.taken_at > MAX_UPLOAD_DELAY:
        return _rejected(
            photo, path, uploaded, "uploaded more than 24h after it was taken"
        )
    reading = reader(photo.jpeg_b64)
    return PhotoRecord(
        sha=photo.sha,
        name=path.name,
        taken_at=photo.taken_at.isoformat(),
        uploaded_at=uploaded.isoformat(),
        kind=reading.kind,
        page=reading.page_number,
        isbn=reading.isbn,
        text=reading.text,
    )


def process_inbox(
    paths: Paths,
    *,
    reader: Callable[[str], Reading] = read_photo,
    now: float | None = None,
) -> InboxResult:
    """Read every settled photo in the inbox into the cache.

    Stops at the first Claude failure: later photos would fail the same way,
    and each one left in the inbox is retried intact.
    """
    clock = time.time() if now is None else now
    records = _photos.load(paths.photos)
    result = InboxResult()
    for path in _candidates(paths.inbox, clock):
        if not path.exists():
            continue  # filed away by another pass between listing and now
        photo = open_photo(path)
        if photo is None:
            result.deferred.append(path.name)
            continue
        if photo.sha in records:
            _file_away(path, paths.processed, photo.sha)
            result.duplicates += 1
            continue
        uploaded = datetime.fromtimestamp(path.stat().st_mtime, tz=UTC)
        try:
            record = _record(photo, path, uploaded, reader)
        except ClaudeUnavailableError as exc:
            _logger.warning("could not read %s (%s); retrying later", path.name, exc)
            result.deferred.append(path.name)
            break
        records[photo.sha] = record
        _photos.save(paths.photos, records)
        _file_away(path, paths.processed, photo.sha)
        result.read.append(record)
        if record.kind == ISBN and record.isbn:
            result.new_isbns.append(record.isbn)
    return result


def unsettled(inbox: Path, *, now: float | None = None) -> int:
    """How many image files are still inside the upload-settle window."""
    if not inbox.is_dir():
        return 0
    clock = time.time() if now is None else now
    return sum(
        1
        for p in inbox.iterdir()
        if p.is_file()
        and p.suffix.lower() in _SUFFIXES
        and clock - p.stat().st_mtime < UPLOAD_SETTLE_SECONDS
    )
