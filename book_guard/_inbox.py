# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Read new photos from the upload inbox into the photo cache.

Run by the ``.path`` unit the moment dufs-cloud writes a file, and by a
15-minute timer as the fallback. Idempotent: a photo already in the cache is
just filed away.

Three outcomes per file, and only the first two move it out of the inbox:

* **read** -- cached as a page / ISBN / other / table of contents, or as
  rejected with a reason (no capture time, uploaded too late);
* **duplicate** -- same bytes as a cached photo;
* **not yet** -- still settling, undecodable (half-uploaded), or a contents
  photo while Claude was unreachable. Left where it is, nothing recorded,
  retried next trigger.

Page photos never wait for Claude: a page number the phone read (its
sidecar note) is taken as is, and only a photo without one has its number
read on this PC (:mod:`book_guard._reader`).
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from datetime import UTC, datetime
import logging
import time
from typing import TYPE_CHECKING, Final

from book_guard import _ledger, _photos
from book_guard._claude import ClaudeUnavailableError
from book_guard._constants import MAX_UPLOAD_DELAY, UPLOAD_SETTLE_SECONDS
from book_guard._errlog import log_error
from book_guard._photo import open_photo
from book_guard._photo_context import context_for, read_sidecar, sidecar_path
from book_guard._photos import OK, REJECTED, PhotoRecord
from book_guard._reader import read
from book_guard._thumbs import make_thumb
from book_guard._toc import TOC_PREFIX, read_toc
from book_guard._vision import ISBN

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

    from book_guard._books import Chapter
    from book_guard._ledger import Ledger
    from book_guard._pagenum import Box, Context
    from book_guard._paths import Paths
    from book_guard._photo import PhotoFile
    from book_guard._vision import Reading

    Reader = Callable[[Path, Context, Box | None], Reading]
    TocReader = Callable[[Path, str], tuple[Chapter, ...]]

_logger: Final = logging.getLogger(__name__)

_SUFFIXES: Final = {".jpg", ".jpeg", ".png", ".webp"}


@dataclass
class InboxResult:
    """What one pass did, for the log and the CLI."""

    read: list[PhotoRecord] = field(default_factory=list)
    duplicates: int = 0
    deferred: list[str] = field(default_factory=list)
    new_isbns: list[str] = field(default_factory=list)
    contents: list[tuple[Chapter, ...]] = field(default_factory=list)


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


def _file_away(path: Path, paths: Paths, sha: str, rotation: int = 0) -> None:
    paths.processed.mkdir(parents=True, exist_ok=True)
    target = paths.processed / f"{sha[:12]}-{path.name}"
    path.replace(target)
    sidecar_path(path).unlink(missing_ok=True)
    make_thumb(target, paths.thumbs, rotation)


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


def _contents_record(
    photo: PhotoFile, path: Path, uploaded: datetime, chapters: tuple[Chapter, ...]
) -> PhotoRecord:
    """A contents photo: not session evidence, so no clock checks."""
    return PhotoRecord(
        sha=photo.sha,
        name=path.name,
        taken_at=photo.taken_at.isoformat() if photo.taken_at else "",
        uploaded_at=uploaded.isoformat(),
        kind="toc",
        text="\n".join(f"{c.start}\t{c.title}" for c in chapters),
    )


def _record(
    photo: PhotoFile,
    path: Path,
    uploaded: datetime,
    reader: Reader,
    known: tuple[dict[str, PhotoRecord], Ledger],
) -> tuple[PhotoRecord, int]:
    """Classify one photo against the ``known`` photo cache and ledger.

    Returns the record and the turn that makes it upright (for the thumb).
    """
    if photo.taken_at is None:
        return _rejected(photo, path, uploaded, "no EXIF capture time"), 0
    if uploaded - photo.taken_at > MAX_UPLOAD_DELAY:
        reason = "uploaded more than 7 days after it was taken"
        return _rejected(photo, path, uploaded, reason), 0
    records, ledger = known
    note = read_sidecar(path)
    context = replace(
        context_for(path.name, photo.taken_at, records, ledger), hint=note.hint
    )
    reading = reader(path, context, note.box)
    record = PhotoRecord(
        sha=photo.sha,
        name=path.name,
        taken_at=photo.taken_at.isoformat(),
        uploaded_at=uploaded.isoformat(),
        kind=reading.kind,
        page=reading.page_number,
        isbn=reading.isbn,
        text=reading.text,
        status=REJECTED if reading.reason else OK,
        reason=reading.reason,
    )
    return record, reading.rotation


def process_inbox(
    paths: Paths,
    *,
    reader: Reader = read,
    toc_reader: TocReader = read_toc,
    now: float | None = None,
) -> InboxResult:
    """Read every settled photo in the inbox into the cache.

    Stops at the first Claude failure: later photos would fail the same way,
    and each one left in the inbox is retried intact.
    """
    clock = time.time() if now is None else now
    records = _photos.load(paths.photos)
    ledger = _ledger.load(paths.ledger, paths.key_file)
    result = InboxResult()
    for path in _candidates(paths.inbox, clock):
        if not path.exists():
            continue  # filed away by another pass between listing and now
        photo = open_photo(path)
        if photo is None:
            result.deferred.append(path.name)
            continue
        if photo.sha in records:
            _file_away(path, paths, photo.sha)
            result.duplicates += 1
            continue
        uploaded = datetime.fromtimestamp(path.stat().st_mtime, tz=UTC)
        chapters: tuple[Chapter, ...] = ()
        rotation = 0
        try:
            if path.name.startswith(TOC_PREFIX):
                chapters = toc_reader(path, photo.jpeg_b64)
                record = _contents_record(photo, path, uploaded, chapters)
            else:
                record, rotation = _record(
                    photo, path, uploaded, reader, (records, ledger)
                )
        except ClaudeUnavailableError as exc:
            _logger.warning("could not read %s (%s); retrying later", path.name, exc)
            result.deferred.append(path.name)
            break
        records[photo.sha] = record
        _photos.save(paths.photos, records)
        if record.status == REJECTED:
            log_error(
                paths,
                "photo",
                record.reason,
                photo=path.name,
                kind=record.kind,
                rotation=rotation,
            )
        _file_away(path, paths, photo.sha, rotation)
        result.read.append(record)
        if record.kind == ISBN and record.isbn:
            result.new_isbns.append(record.isbn)
        if chapters:
            result.contents.append(chapters)
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
