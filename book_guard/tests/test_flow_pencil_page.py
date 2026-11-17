# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A pencilled number is only a suggestion: it rides on the photo record.

The reader finds it when the printed-number reader found nothing; it never
becomes ``page``. The app's keypad pre-fills from ``pencil_page`` in
``state.json`` and the user's tap sends the normal ``type_page`` request.
"""

from __future__ import annotations

from dataclasses import replace
import json
from typing import TYPE_CHECKING

from PIL import Image

from book_guard import _photos, _reader, _reread, _state_json
from book_guard._app_handlers import HANDLERS
from book_guard._ocr import Scan
from book_guard._pagenum import Context
from book_guard._photos import OK, REJECTED
from book_guard._requests import handle_requests
from book_guard._vision import OTHER, PAGE, Reading
from book_guard.tests._flow_helpers import T0, rec, seed_photos

if TYPE_CHECKING:
    from pathlib import Path

    import pytest

    from book_guard._paths import Paths


def _reading(pencil: int | None) -> Reading:
    return Reading(
        OTHER,
        None,
        None,
        "text",
        reason="no page number found",
        pencil_page=pencil,
    )


def test_the_reader_suggests_a_pencilled_number_for_an_unread_page(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:

    page = Scan(0, (100, 100), (), "t" * 300, Image.new("L", (100, 100), 255))
    path = tmp_path / "p.jpg"
    Image.new("RGB", (80, 60), "white").save(path)
    monkeypatch.setattr(_reader, "barcode_isbn", lambda _p: None)
    monkeypatch.setattr(_reader, "scan", lambda _p: page)
    monkeypatch.setattr(_reader, "candidates", lambda _s: [])
    monkeypatch.setattr(_reader, "sparse_candidates", lambda _s: [])
    monkeypatch.setattr(_reader, "margin_candidates", lambda _s: [])
    monkeypatch.setattr(_reader, "read_pencil_page", lambda _s: 29)
    reading = _reader.read(path, Context())
    assert (reading.kind, reading.page_number) == (OTHER, None)
    assert reading.pencil_page == 29
    assert reading.reason  # still rejected: the number is only a suggestion


def test_the_reader_does_not_ask_for_pencil_when_a_number_was_found(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:

    page = Scan(0, (100, 100), (), "t" * 300, Image.new("L", (100, 100), 255))
    path = tmp_path / "p.jpg"
    Image.new("RGB", (80, 60), "white").save(path)
    monkeypatch.setattr(_reader, "barcode_isbn", lambda _p: None)
    monkeypatch.setattr(_reader, "scan", lambda _p: page)
    monkeypatch.setattr(_reader, "candidates", lambda _s: [7])

    def boom(_s: object) -> int:
        msg = "pencil asked although a number was found"
        raise AssertionError(msg)

    monkeypatch.setattr(_reader, "read_pencil_page", boom)
    reading = _reader.read(path, Context())
    assert (reading.kind, reading.page_number, reading.pencil_page) == (PAGE, 7, None)


def _inbox_one(paths: Paths, pencil: int | None) -> str:
    """A rejected photo as the cache holds it, with the phone's pre-fill."""
    record = replace(
        rec("start_a", None, T0, kind=OTHER, status=REJECTED), pencil_page=pencil
    )
    seed_photos(paths, record)
    paths.processed.mkdir(parents=True, exist_ok=True)
    (paths.processed / f"{record.sha[:12]}-{record.name}").write_bytes(b"jpeg")
    return record.name


def test_the_suggestion_rides_on_a_rejected_record_never_as_page(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _inbox_one(bg_paths, 29)
    (record,) = _photos.load(bg_paths.photos).values()
    assert (record.kind, record.page, record.status) == (OTHER, None, REJECTED)
    assert record.pencil_page == 29


def test_no_suggestion_is_none_and_old_caches_load(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _inbox_one(bg_paths, None)
    (record,) = _photos.load(bg_paths.photos).values()
    assert record.pencil_page is None
    raw = json.loads(bg_paths.photos.read_text())
    del raw[record.sha]["pencil_page"]
    bg_paths.photos.write_text(json.dumps(raw))
    assert _photos.load(bg_paths.photos)[record.sha].pencil_page is None


def test_state_json_publishes_the_suggestion_on_the_photo_entry(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _inbox_one(bg_paths, 29)
    entry = _state_json._photos(bg_paths)[0]
    assert (entry["page"], entry["status"], entry["pencil_page"]) == (
        None,
        REJECTED,
        29,
    )


def test_confirming_the_suggestion_is_the_normal_typed_request(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    name = _inbox_one(bg_paths, 29)
    (record,) = _photos.load(bg_paths.photos).values()
    filed = bg_paths.processed / f"{record.sha[:12]}-{name}"
    assert filed.is_file()

    def read(_path: Path, context: Context) -> Reading:
        return Reading(PAGE, context.hint, None, "words")

    monkeypatch.setattr(_reread, "read", read)
    bg_paths.requests.mkdir(parents=True, exist_ok=True)
    body = {"id": "req-type-9", "type": "type_page", "photo": name, "page": 29}
    (bg_paths.requests / "req-type-9.json").write_text(json.dumps(body))
    assert handle_requests(bg_paths, HANDLERS) == 1
    (record,) = _photos.load(bg_paths.photos).values()
    assert (record.page, record.status, record.page_source) == (29, OK, "typed")


def test_a_box_reread_keeps_or_clears_the_suggestion(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    record = rec("start_b", None, T0, kind=OTHER, status=REJECTED)
    seed_photos(bg_paths, record)
    bg_paths.processed.mkdir(parents=True, exist_ok=True)
    (bg_paths.processed / f"{record.sha[:12]}-{record.name}").write_bytes(b"jpeg")

    def read(_path: Path, _context: Context) -> Reading:
        return _reading(12)

    monkeypatch.setattr(_reread, "read", read)
    request = {"photo": "start_b.jpg", "box": [1, 2, 30, 40], "page": 7}
    assert _reread.box_photo(bg_paths, request).code == "no_page"
    (kept,) = _photos.load(bg_paths.photos).values()
    assert kept.pencil_page == 12
