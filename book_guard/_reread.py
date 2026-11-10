# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The app's ``box`` request: read a filed photo again, inside a drawn box.

For a photo the PC could not pin a page number on ("no page number found",
"page number unclear (51 or 3)"). The reader boxes the number on the phone;
the number the phone read in that box (``page``) is the page, taken as is.
Only a request without one has the PC read the box itself. Only a photo
that was *not* read as a page can be re-read: an accepted page may already
be part of a credited session.
"""

from __future__ import annotations

from dataclasses import replace
import logging
from typing import TYPE_CHECKING, Any, Final

from book_guard import _ledger, _photos
from book_guard._flock import exclusive
from book_guard._photo_context import context_for, parse_box
from book_guard._photos import OK, REJECTED
from book_guard._reader import read
from book_guard._requests import Response
from book_guard._vision import PAGE

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
