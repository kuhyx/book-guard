# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Publish the snapshot to the WebDAV folder: NEXT.txt and state.json."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Final

from book_guard._atomic_json import write_json, write_text
from book_guard._render import status_lines
from book_guard._session_files import write_session_files
from book_guard._state_json import to_json
from book_guard._thumbs import backfill

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._state import Snapshot

_logger: Final = logging.getLogger(__name__)


def write_next_file(paths: Paths, snap: Snapshot) -> None:
    """Refresh NEXT.txt and state.json in the WebDAV folder, for the phone.

    Best effort: a failed write is logged, never raised -- the note is a
    convenience, the ledger is the record.
    """
    body = "\n".join(
        [
            "book-guard -- open this after uploading photos.",
            "",
            *status_lines(snap),
            "",
            "How: photo of the open page when you START, photo when you STOP,",
            "then a photo of the check page named above. Upload all to",
            "Reading/inbox with the dufs app. Page numbers must be visible.",
        ]
    )
    backfill(paths.processed, paths.thumbs)
    write_session_files(paths, snap)
    try:
        write_text(paths.next_file, body + "\n")
        write_json(paths.state_file, to_json(paths, snap), indent=1)
    except OSError as exc:
        _logger.warning("could not write %s: %s", paths.next_file, exc)
