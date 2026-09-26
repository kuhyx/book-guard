# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_photo: EXIF capture time and opening (possibly half-written) images."""

from __future__ import annotations

import base64
from datetime import UTC, datetime, timedelta, timezone
import hashlib
import io
from typing import TYPE_CHECKING

from PIL import Image
import pytest

from book_guard import _photo

if TYPE_CHECKING:
    from pathlib import Path

_EXIF_IFD = 0x8769
_DATETIME_ORIGINAL = 0x9003
_OFFSET_TIME_ORIGINAL = 0x9011
_DATETIME = 0x0132
_OFFSET_TIME = 0x9010


def _jpeg(
    path: Path,
    *,
    original: str | None = None,
    original_offset: str | None = None,
    ifd0: str | None = None,
    offset: str | None = None,
    size: tuple[int, int] = (40, 30),
) -> Path:
    exif = Image.Exif()
    if ifd0 is not None:
        exif[_DATETIME] = ifd0
    ifd = exif.get_ifd(_EXIF_IFD)
    for tag, value in (
        (_DATETIME_ORIGINAL, original),
        (_OFFSET_TIME_ORIGINAL, original_offset),
        (_OFFSET_TIME, offset),
    ):
        if value is not None:
            ifd[tag] = value
    Image.new("RGB", size, (200, 180, 160)).save(path, "JPEG", exif=exif)
    return path


def _taken(path: Path) -> datetime | None:
    with Image.open(path) as image:
        return _photo.capture_time(image)


def _local(stamp: str) -> datetime:
    """The same wall-clock digits, read in this machine's zone."""
    return datetime.fromisoformat(stamp).astimezone()


def test_datetime_original_with_offset(tmp_path: Path) -> None:
    path = _jpeg(
        tmp_path / "a.jpg",
        original="2026:10:01 21:04:05",
        original_offset="+02:00",
        ifd0="2026:10:02 00:00:00",
        offset="-05:00",
    )
    taken = _taken(path)
    tz = timezone(timedelta(hours=2))
    assert taken == datetime(2026, 10, 1, 21, 4, 5, tzinfo=tz)
    assert taken is not None
    assert taken.utcoffset() == timedelta(hours=2)


def test_ifd0_datetime_and_offset_fallback(tmp_path: Path) -> None:
    path = _jpeg(tmp_path / "b.jpg", ifd0="2026:10:01 08:30:00", offset="-05:30")
    taken = _taken(path)
    assert taken is not None
    assert taken.utcoffset() == -timedelta(hours=5, minutes=30)
    assert (taken.hour, taken.minute) == (8, 30)


def test_missing_offset_is_local_zone(tmp_path: Path) -> None:
    path = _jpeg(tmp_path / "c.jpg", original="2026:10:01 21:04:05")
    taken = _taken(path)
    assert taken == _local("2026-10-01T21:04:05")
    assert taken is not None
    assert (taken.hour, taken.minute) == (21, 4)
    assert taken.tzinfo is not None


@pytest.mark.parametrize("bad", ["Z", "+2", "+ab:cd", "02:00", "+01:00:00", ""])
def test_malformed_offset_is_local_zone(tmp_path: Path, bad: str) -> None:
    path = _jpeg(
        tmp_path / "d.jpg", original="2026:10:01 21:04:05", original_offset=bad
    )
    assert _taken(path) == _local("2026-10-01T21:04:05")


def test_no_timestamp_at_all(tmp_path: Path) -> None:
    assert _taken(_jpeg(tmp_path / "e.jpg")) is None


@pytest.mark.parametrize(
    "stamp", ["not a date", "2026-10-01 21:04:05", "2026:13:40 25:61:00"]
)
def test_malformed_stamps(tmp_path: Path, stamp: str) -> None:
    assert _taken(_jpeg(tmp_path / "f.jpg", original=stamp)) is None


def test_open_photo_reads_and_downscales(tmp_path: Path) -> None:
    path = _jpeg(
        tmp_path / "big.jpg",
        original="2026:10:01 21:04:05",
        original_offset="+00:00",
        size=(3200, 800),
    )
    photo = _photo.open_photo(path)
    assert photo is not None
    assert photo.sha == hashlib.sha256(path.read_bytes()).hexdigest()
    assert photo.sha == _photo.sha256_of(path)
    assert photo.taken_at == datetime(2026, 10, 1, 21, 4, 5, tzinfo=UTC)
    with Image.open(io.BytesIO(base64.b64decode(photo.jpeg_b64))) as copy:
        assert copy.format == "JPEG"
        assert copy.size == (1600, 400)


def test_open_photo_converts_non_rgb(tmp_path: Path) -> None:
    path = tmp_path / "p.png"
    Image.new("RGBA", (10, 10)).save(path)
    photo = _photo.open_photo(path)
    assert photo is not None
    assert photo.taken_at is None


def test_open_photo_half_written(tmp_path: Path) -> None:
    full = _jpeg(tmp_path / "full.jpg", size=(400, 400))
    half = tmp_path / "half.jpg"
    half.write_bytes(full.read_bytes()[:300])
    assert _photo.open_photo(half) is None


def test_open_photo_not_an_image(tmp_path: Path) -> None:
    junk = tmp_path / "junk.jpg"
    junk.write_bytes(b"definitely not a jpeg")
    assert _photo.open_photo(junk) is None
    assert _photo.open_photo(tmp_path / "missing.jpg") is None
