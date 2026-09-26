# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Everything read from a photo file without asking a model.

The EXIF capture time is the session clock. It survives the phone upload
(dufs-cloud's uploader sends the camera's bytes untouched -- checked on two
Pixel 6a photos in ~/data/cloud, 2026-09-26), and it is what separates "I read
from 21:04 to 21:38" from "I uploaded two photos at 21:40".
"""

from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta, timezone
import hashlib
import io
import logging
import re
from typing import TYPE_CHECKING, Final

from PIL import Image, UnidentifiedImageError

if TYPE_CHECKING:
    from pathlib import Path

_logger: Final = logging.getLogger(__name__)

_EXIF_IFD: Final = 0x8769
_DATETIME_ORIGINAL: Final = 0x9003
_OFFSET_TIME_ORIGINAL: Final = 0x9011
_DATETIME: Final = 0x0132
_OFFSET_TIME: Final = 0x9010
_EXIF_STAMP: Final = re.compile(r"(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})")
_OFFSET_PARTS: Final = 2
_MAX_EDGE: Final = 1600
"""Downscale before sending: a 12 MP phone photo costs far more tokens than a
page of text needs, and 1600 px still reads 9 pt print."""


@dataclass(frozen=True)
class PhotoFile:
    """A readable photo: its identity, capture time and a model-ready copy."""

    sha: str
    taken_at: datetime | None
    jpeg_b64: str


def sha256_of(path: Path) -> str:
    """The content hash that keys the photo cache."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _parse_offset(raw: object) -> timezone | None:
    """``+02:00`` as a tzinfo, or ``None`` when absent or malformed."""
    text = str(raw or "").strip()
    sign = {"+": 1, "-": -1}.get(text[:1])
    parts = text[1:].split(":")
    if (
        sign is None
        or len(parts) != _OFFSET_PARTS
        or not all(p.isdigit() for p in parts)
    ):
        return None
    return timezone(sign * timedelta(hours=int(parts[0]), minutes=int(parts[1])))


def capture_time(image: Image.Image) -> datetime | None:
    """The EXIF capture time as an aware datetime, or ``None``.

    A missing offset is read as this machine's local zone -- the phone and
    the PC live in the same timezone, and a photo without an offset is still
    better evidence than none.
    """
    exif = image.getexif()
    ifd = exif.get_ifd(_EXIF_IFD)
    raw = ifd.get(_DATETIME_ORIGINAL)
    offset_raw = ifd.get(_OFFSET_TIME_ORIGINAL)
    if not raw:
        # Photos taken through the in-app camera (Android camera intent, via
        # image_picker) carry no DateTimeOriginal -- only IFD0 DateTime and
        # OffsetTime, which the camera stamps at capture (measured on the
        # Pixel 6a, 2026-09-26: DateTime = shutter time to the second).
        raw = exif.get(_DATETIME)
        offset_raw = ifd.get(_OFFSET_TIME)
    if not raw:
        return None
    match = _EXIF_STAMP.fullmatch(str(raw).strip())
    if match is None:
        return None
    offset = _parse_offset(offset_raw)
    try:
        year, month, day, hour, minute, second = (int(g) for g in match.groups())
        stamp = datetime(year, month, day, hour, minute, second, tzinfo=offset or UTC)
    except ValueError:
        _logger.warning("EXIF capture time %r is not a real date", raw)
        return None
    # No offset: the wall-clock digits are local time, so re-attach the
    # machine's zone to those same digits rather than converting from UTC.
    return stamp if offset else stamp.replace(tzinfo=None).astimezone()


def open_photo(path: Path) -> PhotoFile | None:
    """Read ``path``, or ``None`` if it is not (yet) a complete image.

    ``None`` covers a half-uploaded file too: the caller leaves it in the
    inbox and retries on the next trigger rather than recording a failure.
    """
    try:
        with Image.open(path) as image:
            image.load()
            taken = capture_time(image)
            copy = image.convert("RGB")
    except (OSError, UnidentifiedImageError, SyntaxError) as exc:
        _logger.warning("%s is not (yet) a readable image: %s", path.name, exc)
        return None
    copy.thumbnail((_MAX_EDGE, _MAX_EDGE))
    buffer = io.BytesIO()
    copy.save(buffer, format="JPEG", quality=85)
    return PhotoFile(
        sha=sha256_of(path),
        taken_at=taken,
        jpeg_b64=base64.b64encode(buffer.getvalue()).decode("ascii"),
    )
