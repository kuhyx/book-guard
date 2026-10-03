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


def test_a_box_the_phone_read_differently_is_not_trusted(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A misread "108" in a stop photo's box must not beat the phone's 103."""
    path = _jpeg(tmp_path)
    _reader_with(monkeypatch, page=_page(), found=[3, 103], boxed=[108])
    context = Context(after=51, hint=103)
    assert _reader.read(path, context, (10, 10, 20, 20)).page_number == 103
    # Agreeing readers: the box decides.
    _reader_with(monkeypatch, page=_page(), found=[3], boxed=[103])
    assert _reader.read(path, context, (10, 10, 20, 20)).page_number == 103
