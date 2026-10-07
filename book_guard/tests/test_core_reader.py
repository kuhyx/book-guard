# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_reader: barcode, then the page read locally, never a model."""

from __future__ import annotations

from typing import TYPE_CHECKING

from PIL import Image

from book_guard import _reader
from book_guard._ocr import Scan
from book_guard._pagenum import Context
from book_guard._vision import ISBN, OTHER, PAGE, Reading

if TYPE_CHECKING:
    from pathlib import Path

    import pytest


def _jpeg(tmp_path: Path) -> Path:
    path = tmp_path / "p.jpg"
    Image.new("RGB", (80, 60), "white").save(path)
    return path


def _page(text: str = "t" * 300, rotation: int = 0) -> Scan:
    return Scan(
        rotation=rotation,
        size=(100, 100),
        words=(),
        text=text,
        image=Image.new("L", (100, 100), 255),
    )


def _reader_with(
    monkeypatch: pytest.MonkeyPatch,
    *,
    page: Scan | None,
    found: list[int],
    boxed: list[int] | None = None,
    isbn: str | None = None,
) -> None:
    monkeypatch.setattr(_reader, "barcode_isbn", lambda _p: isbn)
    monkeypatch.setattr(_reader, "scan", lambda _p: page)
    monkeypatch.setattr(_reader, "candidates", lambda _s: found)
    monkeypatch.setattr(_reader, "read_box", lambda _img, _box: boxed or [])


def test_reader_barcode_needs_nothing_else(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _reader_with(monkeypatch, page=None, found=[], isbn="9788368380002")
    assert _reader.read(_jpeg(tmp_path), Context()) == Reading(
        ISBN, None, "9788368380002", ""
    )


def test_reader_without_tesseract(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _reader_with(monkeypatch, page=None, found=[])
    reading = _reader.read(_jpeg(tmp_path), Context())
    assert (reading.kind, reading.reason) == (OTHER, "the PC could not read the photo")


def test_reader_page(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _reader_with(monkeypatch, page=_page(rotation=180), found=[3, 51])
    reading = _reader.read(_jpeg(tmp_path), Context(near=51))
    assert reading == Reading(PAGE, 51, None, "t" * 300, rotation=180)


def test_reader_printed_isbn(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _reader_with(monkeypatch, page=_page("ISBN 978-83-6838-000-2\nwydanie"), found=[])
    reading = _reader.read(_jpeg(tmp_path), Context())
    assert (reading.kind, reading.isbn) == (ISBN, "9788368380002")
    _reader_with(monkeypatch, page=_page("ISBN 83-1234-567-8 short"), found=[])
    assert _reader.read(_jpeg(tmp_path), Context()).reason == "no page on the photo"


def test_reader_unclear_asks_for_a_box(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _reader_with(monkeypatch, page=_page(), found=[3, 51])
    reading = _reader.read(_jpeg(tmp_path), Context())
    assert reading.kind == OTHER
    assert reading.reason.startswith("page number unclear (3 or 51) -- box")
    assert reading.text == "t" * 300


def test_reader_box_is_read_first(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = _jpeg(tmp_path)
    _reader_with(monkeypatch, page=_page(), found=[3], boxed=[7])
    assert _reader.read(path, Context(near=51), (10, 10, 20, 20)).page_number == 7
    # Nothing legible in the box: the whole page decides, unboxed.
    _reader_with(monkeypatch, page=_page(), found=[51], boxed=[])
    assert _reader.read(path, Context(near=51), (10, 10, 20, 20)).page_number == 51
    # A box entirely off the image reads as nothing at all.
    _reader_with(monkeypatch, page=_page(), found=[51], boxed=[9])
    assert _reader.read(path, Context(near=51), (500, 500, 600, 600)).page_number == 51


def test_the_phones_page_is_final_and_the_pc_only_transcribes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """No barcode, candidates, box or plausibility check can overrule it."""
    path = _jpeg(tmp_path)
    _reader_with(
        monkeypatch,
        page=_page(rotation=90),
        found=[3, 51],
        boxed=[108],
        isbn="9788368380002",
    )
    context = Context(after=51, last_page=60, hint=103)  # 103 is "implausible"
    reading = _reader.read(path, context, (10, 10, 20, 20))
    assert reading == Reading(PAGE, 103, None, "t" * 300, rotation=90)
    # Even a page with next to no text is a page when the phone read a number.
    _reader_with(monkeypatch, page=_page("blur"), found=[])
    assert _reader.read(path, Context(hint=7)) == Reading(PAGE, 7, None, "blur")


def test_the_phones_page_survives_a_photo_the_pc_cannot_scan(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    _reader_with(monkeypatch, page=None, found=[])
    reading = _reader.read(_jpeg(tmp_path), Context(hint=42))
    assert reading == Reading(PAGE, 42, None, "")
    assert "phone's p. 42 kept" in caplog.text


def test_without_the_phones_page_the_pc_reads_it_itself(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The fallback (desktop web upload, "Send anyway"): plausibility decides."""
    path = _jpeg(tmp_path)
    _reader_with(monkeypatch, page=_page(), found=[3, 103], boxed=[108])
    assert _reader.read(path, Context(after=51)).page_number == 103
    assert _reader.read(path, Context(after=51), (10, 10, 20, 20)).page_number == 108


def test_box_readings_are_evidence_not_a_verdict(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A real p. 85 crop read 86, 85 and 856 under different settings."""
    path = _jpeg(tmp_path)
    box = (10, 10, 20, 20)
    _reader_with(monkeypatch, page=_page(), found=[], boxed=[86, 85, 856])
    # A check photo: the page asked for is among them.
    assert _reader.read(path, Context(expected=85), box).page_number == 85
    # Not a check photo: the most frequent reading.
    assert _reader.read(path, Context(near=80), box).page_number == 86
