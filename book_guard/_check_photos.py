# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The retired check page: still drawn, so old check photos pair as before.

Until :data:`~book_guard._constants.CHECK_DROP_DATE` a session asked for a
third photo, of a page drawn from its start..stop pages by the photos'
hashes. None is asked for now, but the pairing still claims the old check
photos so every session id stays what it was.
"""

from __future__ import annotations

import hashlib
import re
from typing import TYPE_CHECKING, Final

from book_guard._constants import CHECK_DROP_DATE

if TYPE_CHECKING:
    from book_guard._photos import PhotoRecord
    from book_guard._sessions import Session

_CHECK_LABEL: Final = re.compile(r"^check\d+_")


def check_page_for(start: PhotoRecord, end: PhotoRecord) -> int | None:
    """The page to photograph as proof: from the start page to the stop page.

    Both ends are drawn from (a one-page session names its own page); ``None``
    only when the stop page is before the start page.
    """
    low, high = int(start.page or 0), int(end.page or 0)
    if high < low:
        return None
    seed = hashlib.sha256((start.sha + end.sha).encode()).digest()
    return low + int.from_bytes(seed[:8], "big") % (high - low + 1)


def _may_be_check(photo: PhotoRecord) -> bool:
    """Taken while check pages were asked for, or labelled one by an old app."""
    before = photo.taken.astimezone().date() < CHECK_DROP_DATE
    return before or _CHECK_LABEL.match(photo.name) is not None


def claims_check(pending: list[Session], photo: PhotoRecord) -> bool:
    """Attach ``photo`` as the check photo of the first session it answers."""
    if not _may_be_check(photo):
        return False
    for session in pending:
        if session.check_page == photo.page and photo.taken > session.end.taken:
            session.check = photo
            pending.remove(session)
            return True
    return False
