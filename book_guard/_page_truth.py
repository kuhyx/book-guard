# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A page the reader had to correct becomes a ``scripts/page_truth.py`` row.

The phone's sidecar carries ``ocr_page``, what its OCR alone offered, beside
``page``, the number the reader confirmed or fixed. When they differ the OCR
was wrong on a real photo, so the photo is copied into the page-truth folder
(``Paths.page_truth_dir``, outside the repo) with a row in its
``manifest.json``: ``scripts/page_truth.py`` then fails until the reader is
fixed. The error log gets an ``ocr corrected`` line either way.

Locking: no lock of its own. The one caller is the inbox pass, which already
holds the book-guard write lock (:func:`book_guard._flock.exclusive`), so it
is the manifest's only writer; the manifest is replaced atomically (temp file
and rename), so ``page_truth.py`` never reads half of it. This is photos-first
code: any failure is logged and swallowed, never raised into the photo pass.
"""

from __future__ import annotations

from dataclasses import asdict
from datetime import date, datetime
import json
import logging
import shutil
from typing import TYPE_CHECKING, Final

from book_guard._atomic_json import write_json
from book_guard._errlog import log_error

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._pagenum import Context
    from book_guard._paths import Paths
    from book_guard._photo_context import Sidecar

_logger: Final = logging.getLogger(__name__)

OCR_CORRECTED: Final = "ocr corrected"
TRUTH_FAILED: Final = "page_truth row not written"
MANIFEST: Final = "manifest.json"
_SHA_PREFIX: Final = 12


def _row(
    file: str, context: Context, ocr_page: int, page: int, today: date
) -> dict[str, object]:
    """The manifest row: what ``scripts/page_truth.py`` expects, plus ``ocr_page``."""
    fields = {k: v for k, v in asdict(context).items() if v is not None and k != "hint"}
    return {
        "file": file,
        "context": fields,
        "page": page,
        "ocr_page": ocr_page,
        "why": f"{today.isoformat()}: the phone's OCR offered {ocr_page}, "
        f"the reader corrected it to {page}",
    }


def _add_row(paths: Paths, photo: Path, row: dict[str, object]) -> None:
    """Copy the photo and append ``row`` unless its file is already listed."""
    folder = paths.page_truth_dir
    manifest = folder / MANIFEST
    rows: list[dict[str, object]] = []
    if manifest.exists():
        loaded = json.loads(manifest.read_text(encoding="utf-8"))
        if not isinstance(loaded, list):
            msg = f"{manifest} is not a list of rows"
            raise ValueError(msg)  # one error type for the caller
        rows = loaded
    if any(r.get("file") == row["file"] for r in rows):
        return
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(photo, folder / str(row["file"]))
    write_json(manifest, [*rows, row], indent=2)


def note_ocr_miss(
    paths: Paths, photo: Path, sha: str, context: Context, note: Sidecar
) -> None:
    """If ``note`` shows the OCR offered another page than the reader's, file it.

    Logs ``ocr corrected`` and adds the manifest row; nothing for a photo
    whose ``ocr_page`` is absent or agrees with ``page``.
    """
    ocr_page, page = note.ocr_page, note.hint
    if ocr_page is None or page is None or ocr_page == page:
        return
    log_error(
        paths, "photo", OCR_CORRECTED, photo=photo.name, ocr_page=ocr_page, page=page
    )
    file = f"{sha[:_SHA_PREFIX]}-{photo.name}"
    row = _row(file, context, ocr_page, page, datetime.now().astimezone().date())
    try:
        _add_row(paths, photo, row)
    except (OSError, ValueError) as exc:
        _logger.warning("page_truth row for %s not written (%s)", photo.name, exc)
        log_error(paths, "photo", TRUTH_FAILED, photo=photo.name, detail=str(exc))
