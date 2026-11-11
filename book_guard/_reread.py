# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The app's ``box`` request: read a filed photo again, inside a drawn box.

For a photo the PC could not pin a page number on ("no page number found",
"page number unclear (51 or 3)"). The reader boxes the number on the phone;
the number the phone read in that box (``page``) is the page, taken as is.
Only a request without one has the PC read the box itself. Only a photo
that was *not* read as a page can be re-read: an accepted page may already
be part of a credited session.

The ``type_page`` request is for a page with no printed number (a chapter
opener): the reader types it. It travels like the phone's own reading -- it
is the reader's ``hint``, taken as is, no re-read and no plausibility check --
and the record keeps ``page_source = "typed"`` so the credit can be audited.
"""

from __future__ import annotations

from dataclasses import replace
import logging
from typing import TYPE_CHECKING, Any, Final

from book_guard import _ledger, _photos
from book_guard._flock import exclusive
from book_guard._photo_context import context_for, parse_box
from book_guard._photos import OK, REJECTED, TYPED
from book_guard._reader import read
from book_guard._requests import DeferredError, Response
from book_guard._vision import OTHER, PAGE

if TYPE_CHECKING:
    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)


def box_photo(paths: Paths, request: dict[str, Any]) -> Response:
    """Re-read photo ``request["photo"]`` inside ``request["box"]``."""
    name = request.get("photo")
    box = parse_box(request.get("box"))
    if not isinstance(name, str) or box is None:
        return Response(ok=False, code="no_box")
    with exclusive(paths):
        records = _photos.load(paths.photos)
        record = next((r for r in records.values() if r.name == name), None)
        if record is None or not record.taken_at:
            return Response(ok=False, code="no_photo")
        if record.kind == PAGE and record.status == OK:
            return Response(ok=False, code="already_read", data={"page": record.page})
        filed = paths.processed / f"{record.sha[:12]}-{record.name}"
        if not filed.is_file():
            return Response(ok=False, code="photo_gone")
        others = {sha: r for sha, r in records.items() if sha != record.sha}
        ledger = _ledger.load(paths.ledger, paths.key_file)
        context = context_for(name, record.taken, others, ledger)
        phone = request.get("page")
        if isinstance(phone, int) and not isinstance(phone, bool):
            context = replace(context, hint=phone)
        reading = read(filed, context, box)
        records[record.sha] = replace(
            record,
            kind=reading.kind,
            page=reading.page_number,
            text=reading.text or record.text,
            status=REJECTED if reading.reason else OK,
            reason=reading.reason,
        )
        _photos.save(paths.photos, records)
    if reading.page_number is None:
        _logger.info("box on %s: still no page number: %s", name, reading.reason)
        return Response(ok=False, code="no_page")
    return Response(ok=True, code="read", data={"page": reading.page_number})


MAX_TYPED_PAGE: Final = 9999
"""A typo guard, not a plausibility check: no book here has more pages."""


def type_page(paths: Paths, request: dict[str, Any]) -> Response:
    """Take ``request["page"]`` as the page of photo ``request["photo"]``.

    Only for a photo with no number: a number already read is never
    overridden (``already_read``), and a barcode or contents photo is no page.
    """
    name = request.get("photo")
    page = request.get("page")
    if (
        not isinstance(name, str)
        or not isinstance(page, int)
        or isinstance(page, bool)
        or not 1 <= page <= MAX_TYPED_PAGE
    ):
        return Response(ok=False, code="bad_page")
    with exclusive(paths):
        records = _photos.load(paths.photos)
        record = next((r for r in records.values() if r.name == name), None)
        if record is None and (paths.inbox / name).is_file():
            # The phone queues the number right behind the photo, and the PC
            # answers it before the photo is read (still settling, or its
            # reader was down): wait for the photo, never refuse the number.
            msg = f"{name} is not read yet"
            raise DeferredError(msg)
        if record is None or not record.taken_at:
            return Response(ok=False, code="no_photo")
        if record.page is not None:
            return Response(ok=False, code="already_read", data={"page": record.page})
        if record.kind not in {PAGE, OTHER}:
            return Response(ok=False, code="refused")
        filed = paths.processed / f"{record.sha[:12]}-{record.name}"
        if not filed.is_file():
            return Response(ok=False, code="photo_gone")
        others = {sha: r for sha, r in records.items() if sha != record.sha}
        ledger = _ledger.load(paths.ledger, paths.key_file)
        context = replace(context_for(name, record.taken, others, ledger), hint=page)
        reading = read(filed, context)
        records[record.sha] = replace(
            record,
            kind=PAGE,
            page=page,
            text=reading.text or record.text,
            status=OK,
            reason="",
            page_source=TYPED,
        )
        _photos.save(paths.photos, records)
    _logger.info("typed page %d for %s", page, name)
    return Response(ok=True, code="read", data={"page": page})
