# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A ``kept_`` photo: a stale start/stop kept as a page photo, never a session."""

from __future__ import annotations

from dataclasses import replace
from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

from book_guard import _inbox
from book_guard._photos import KEPT, OK, load, usable_pages
from book_guard._state import snapshot
from book_guard._state_json import to_json
from book_guard.tests._flow_helpers import add_book, rec, seed_photos
from book_guard.tests.test_flow_inbox import (
    NOW,
    UPLOADED,
    _drop,
    _fake_open,
    _page_reader,
    _photo,
)

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths


def test_a_kept_photo_is_filed_but_never_paired(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    # 2026-11-22: a stop photo of 2026-11-12 stored on the phone, kept.
    add_book(bg_paths, pages=611)
    start = rec("start", 250, UPLOADED - timedelta(days=10, minutes=40))
    seed_photos(bg_paths, start)
    name = "kept_IMG.jpg"
    _drop(bg_paths, name, page=290)
    _fake_open(monkeypatch, {name: _photo("kept", UPLOADED - timedelta(days=10))})
    (record,) = _inbox.process_inbox(bg_paths, reader=_page_reader(290), now=NOW).read
    assert (record.status, record.kind, record.page) == (OK, KEPT, 290)
    assert [p.name for p in usable_pages(load(bg_paths.photos))] == ["start.jpg"]
    assert snapshot(bg_paths).sessions == []


def test_a_kept_photo_that_is_no_page_stays_what_it_is(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "kept_x.jpg")  # no number: needs one, as any page photo
    _fake_open(monkeypatch, {"kept_x.jpg": _photo("x")})
    (record,) = _inbox.process_inbox(bg_paths, now=NOW).read
    assert record.kind != KEPT


def test_a_late_upload_is_listed_though_its_exif_is_old(bg_paths: Paths) -> None:
    """2026-11-22: a 10-27 photo sent today, rejected, never in the 40 newest
    by EXIF -- the phone took it for an unread p. 473 start all day."""
    add_book(bg_paths, pages=611)
    now = datetime.now(tz=UTC)
    newer = [
        rec(f"n{i}", 10 + i, now - timedelta(days=3, minutes=i)) for i in range(45)
    ]
    late = replace(
        rec("late", None, now - timedelta(days=26), status="rejected", kind="other"),
        uploaded_at=(now - timedelta(minutes=30)).isoformat(),
    )
    seed_photos(bg_paths, *newer, late)
    names = [p["name"] for p in to_json(bg_paths, snapshot(bg_paths))["photos"]]
    assert len(names) == 41
    assert names[-1] == "late.jpg"
