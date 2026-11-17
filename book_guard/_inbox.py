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

Page photos never wait for Claude: the page number the phone sent (its
sidecar note) is taken as is and is the only one there is -- the PC never
reads a page number. A photo without one is rejected as ``needs number``
(it then shows in the phone's failed photos, where the keypad re-sends it);
only a barcode zbar decodes still makes it an ISBN photo. When the note's
``ocr_page`` differs from its ``page``, the OCR was corrected and the photo
becomes a ``scripts/page_truth.py`` row (:mod:`book_guard._page_truth`).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
import logging
import time
from typing import TYPE_CHECKING, Final

from book_guard import _ebook_sessions, _ledger, _photos
from book_guard._claude import ClaudeUnavailableError
from book_guard._constants import UPLOAD_SETTLE_SECONDS
from book_guard._errlog import log_error
from book_guard._inbox_record import Pass, classify, contents_record
from book_guard._ocr import barcode_isbn
from book_guard._photo import open_photo
from book_guard._photo_context import sidecar_path
from book_guard._photos import REJECTED, PhotoRecord
from book_guard._reader import read
from book_guard._thumbs import make_thumb
from book_guard._toc import TOC_PREFIX, read_toc
from book_guard._vision import ISBN

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

    from book_guard._books import Chapter
    from book_guard._inbox_record import BarcodeReader, Reader
    from book_guard._paths import Paths

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


def process_inbox(
    paths: Paths,
    *,
    reader: Reader = read,
    barcode: BarcodeReader = barcode_isbn,
    toc_reader: TocReader = read_toc,
    now: float | None = None,
) -> InboxResult:
    """Read every settled photo in the inbox into the cache.

    Stops at the first Claude failure: later photos would fail the same way,
    and each one left in the inbox is retried intact.
    """
    clock = time.time() if now is None else now
    # The ledger and the in-app sessions do not change during a pass.
    known = Pass(
        paths,
        reader,
        barcode,
        _photos.load(paths.photos),
        _ledger.load(paths.ledger, paths.key_file),
        _ebook_sessions.sessions(paths),
    )
    result = InboxResult()
    for path in _candidates(paths.inbox, clock):
        if not path.exists():
            continue  # filed away by another pass between listing and now
        photo = open_photo(path)
        if photo is None:
            result.deferred.append(path.name)
            continue
        if photo.sha in known.records:
            _file_away(path, paths, photo.sha)
            result.duplicates += 1
            continue
        uploaded = datetime.fromtimestamp(path.stat().st_mtime, tz=UTC)
        chapters: tuple[Chapter, ...] = ()
        rotation = 0
        try:
            if path.name.startswith(TOC_PREFIX):
                chapters = toc_reader(path, photo.jpeg_b64)
                record = contents_record(photo, path, uploaded, chapters)
            else:
                record, rotation = classify(photo, path, uploaded, known)
        except ClaudeUnavailableError as exc:
            _logger.warning("could not read %s (%s); retrying later", path.name, exc)
            result.deferred.append(path.name)
            break
        known.records[photo.sha] = record
        _photos.save(paths.photos, known.records)
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
