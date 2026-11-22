# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``type_page`` and ``box`` never re-file a photo uploaded 7+ days late."""

from __future__ import annotations

from dataclasses import replace
from datetime import timedelta
from typing import TYPE_CHECKING

import pytest

from book_guard import _photos, _reread
from book_guard._photos import REJECTED
from book_guard._requests import Response
from book_guard._vision import OTHER, PAGE, Reading
from book_guard.tests._flow_helpers import T0, rec, seed_photos

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

    from book_guard._pagenum import Context
    from book_guard._paths import Paths


def _filed(paths: Paths, name: str, uploaded_days: int) -> str:
    """A number-less photo, filed away and uploaded ``uploaded_days`` late."""
    record = rec(name, None, T0, kind=OTHER, status=REJECTED)
    late = (T0 + timedelta(days=uploaded_days)).isoformat()
    seed_photos(paths, replace(record, uploaded_at=late))
    paths.processed.mkdir(parents=True, exist_ok=True)
    (paths.processed / f"{record.sha[:12]}-{record.name}").write_bytes(b"jpeg")
    return record.name


def _read(_path: Path, context: Context) -> Reading:
    return Reading(PAGE, context.hint, None, "words")


@pytest.mark.parametrize("handler", [_reread.type_page, _reread.box_photo])
def test_a_photo_uploaded_too_late_is_never_refiled(
    bg_paths: Paths, handler: Callable[[Paths, dict[str, object]], Response]
) -> None:
    """A start stored on the phone for 26 days stays off every session.

    The PC rejected it as uploaded more than 7 days late; a number typed or
    boxed for it from the failed photos must not turn it into a page.
    """
    name = _filed(bg_paths, "start_a", 26)
    body = {"photo": name, "page": 473, "box": [10, 10, 20, 20]}
    assert handler(bg_paths, body) == Response(ok=False, code="refused")
    (after,) = _photos.load(bg_paths.photos).values()
    assert (after.page, after.status) == (None, REJECTED)


def test_a_late_kept_photo_can_still_be_numbered(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A ``kept_`` page photo is filed off every session, so lateness is fine."""
    name = _filed(bg_paths, "kept_start_a", 26)
    monkeypatch.setattr(_reread, "read", _read)
    response = _reread.type_page(bg_paths, {"photo": name, "page": 473})
    assert response.code == "read"
