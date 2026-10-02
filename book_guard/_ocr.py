# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Reading a photo without a model: barcodes (zbar) and printed text (Tesseract).

Measured on a real page photo (2026-10-02, Czerwony cesarz p. 7): Tesseract
with the Polish model transcribed the body text almost word for word in
1.3 s, where Haiku's transcription invented words. It could not find the
small printed page number on the curved page, though -- margin crops landed
on body text -- so the page number stays the model's job (see ``_reader``).

Both tools are optional at runtime: missing binaries mean "no local reading"
and the caller falls back to the model.
"""

from __future__ import annotations

import io
import logging
import re
import shutil
import subprocess
from typing import TYPE_CHECKING, Final

from PIL import Image, ImageChops, ImageFilter, ImageOps

from book_guard._vision import normalise_isbn

if TYPE_CHECKING:
    from pathlib import Path

_logger: Final = logging.getLogger(__name__)

TEXT_LIMIT: Final = 1500
"""As much body text as the model was asked for: the quiz's evidence."""
_TIMEOUT: Final = 120
_ISBN13_LEN: Final = 13
_HYPHEN_BREAK: Final = re.compile(r"(\w)-\n(\w)")
_BLANKS: Final = re.compile(r"\n\s*\n+")
_BACKGROUND_BLUR: Final = 30
_INK_GAIN: Final = 3


def _run(argv: list[str], stdin: bytes = b"") -> str:
    """A tool's stdout, or "" (logged) if it failed or timed out."""
    try:
        done = subprocess.run(
            argv, input=stdin, capture_output=True, timeout=_TIMEOUT, check=False
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        _logger.warning("%s failed (%s); falling back to the model", argv[0], exc)
        return ""
    return done.stdout.decode("utf-8", errors="replace")


def flatten(gray: Image.Image) -> Image.Image:
    """Ink on white, whatever the lighting.

    Subtract the page's own blurred background, then stretch. A phone photo
    of a curved page is darker
    towards the spine; on the measured photo this doubled the words read
    with confidence and reached the last line instead of stopping halfway.
    """
    background = gray.filter(ImageFilter.GaussianBlur(_BACKGROUND_BLUR))
    ink = ImageChops.subtract(background, gray)
    return Image.eval(ink, lambda v: 255 - min(255, v * _INK_GAIN))


def barcode_isbn(path: Path) -> str | None:
    """The book's ISBN from an EAN-13 barcode in the photo, if zbar finds one."""
    zbar = shutil.which("zbarimg")
    if zbar is None:
        return None
    out = _run([zbar, "--quiet", "--raw", "-Sdisable", "-Sean13.enable", str(path)])
    for line in out.splitlines():
        isbn = normalise_isbn(line)
        if isbn and len(isbn) == _ISBN13_LEN and isbn.startswith(("978", "979")):
            return isbn
    return None


def page_text(path: Path) -> str:
    """The photo's printed text, upright (EXIF), hyphen breaks rejoined."""
    tesseract = shutil.which("tesseract")
    if tesseract is None:
        return ""
    try:
        with Image.open(path) as image:
            upright = ImageOps.exif_transpose(image).convert("L")
    except OSError as exc:
        _logger.warning("cannot open %s for OCR (%s)", path.name, exc)
        return ""
    buffer = io.BytesIO()
    flatten(upright).save(buffer, format="PNG")
    raw = _run([tesseract, "stdin", "-", "-l", "pol", "--psm", "3"], buffer.getvalue())
    text = _BLANKS.sub("\n", _HYPHEN_BREAK.sub(r"\1\2", raw)).strip()
    return text[:TEXT_LIMIT]
