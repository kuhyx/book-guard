# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Small copies of the filed photos, for the app's gallery.

A phone photo is 2-3 MB; the gallery lists dozens. Thumbnails live next to
the originals on the share (``Reading/thumbs/<sha12>.jpg``) so the app can
fetch them with the same login, and the originals stay untouched for the
full-size view.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Final

from PIL import Image, ImageOps

if TYPE_CHECKING:
    from pathlib import Path

_logger: Final = logging.getLogger(__name__)

THUMB_EDGE: Final = 400
_SHA_PREFIX: Final = 12


def thumb_name(filed: str) -> str:
    """``80f8d247d689-start_x.jpg`` -> ``80f8d247d689.jpg``."""
    return f"{filed[:_SHA_PREFIX]}.jpg"


def make_thumb(filed: Path, thumbs: Path, rotation: int = 0) -> None:
    """Write ``filed``'s thumbnail unless it exists; failures are logged only.

    ``rotation``: the reader's upright turn after EXIF, so the gallery shows
    the page the way it was read.
    """
    target = thumbs / thumb_name(filed.name)
    if target.exists():
        return
    try:
        with Image.open(filed) as image:
            small = ImageOps.exif_transpose(image).convert("RGB")
        if rotation:
            small = small.rotate(rotation, expand=True)
        small.thumbnail((THUMB_EDGE, THUMB_EDGE))
        thumbs.mkdir(parents=True, exist_ok=True)
        small.save(target, format="JPEG", quality=80)
    except OSError as exc:
        _logger.warning("no thumbnail for %s (%s)", filed.name, exc)


def backfill(processed: Path, thumbs: Path) -> None:
    """Thumbnails for photos filed before thumbnails existed."""
    if processed.is_dir():
        for filed in sorted(processed.iterdir()):
            if filed.is_file():
                make_thumb(filed, thumbs)
