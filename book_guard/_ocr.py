# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Reading a photo without a model: barcodes (zbar) and printed text (Tesseract).

Measured on a real page photo (2026-10-02, Czerwony cesarz p. 7): Tesseract
with the Polish model transcribed the body text almost word for word in
1.3 s, where Haiku's transcription invented words.

**Upright comes from the page, not EXIF.** A phone pointed straight down at
a book cannot tell which way is up from gravity: the p. 51 photo of
2026-10-03 was tagged "rotated 90 degrees" the wrong way, Tesseract read
mirror-image gibberish and Haiku called it page 19. EXIF is only the first
guess; Tesseract's orientation detection decides, and when it is unsure the
rotation with the most confidently read words wins.

Both tools are optional at runtime: a missing binary means "nothing read".
"""

from __future__ import annotations

from dataclasses import dataclass, field
import io
import logging
import re
import shutil
import subprocess
from typing import TYPE_CHECKING, Final

from PIL import Image, ImageChops, ImageFilter, ImageOps, UnidentifiedImageError

from book_guard._vision import normalise_isbn

if TYPE_CHECKING:
    from pathlib import Path

_logger: Final = logging.getLogger(__name__)

TEXT_LIMIT: Final = 1500
"""As much body text as the quiz takes as evidence."""
_TIMEOUT: Final = 120
_ISBN13_LEN: Final = 13
_HYPHEN_BREAK: Final = re.compile(r"(\w)-\n(\w)")
_BACKGROUND_BLUR: Final = 30
_INK_GAIN: Final = 3
_OSD_EDGE: Final = 1600
_SCORE_EDGE: Final = 1000
OSD_TRUST: Final = 5.0
"""Tesseract's orientation confidence above which it is taken as is.

Measured: 16.3 on the sideways p. 51 photo (right), 0.0 on a dim sideways
retake (useless) -- below this the four rotations are scored instead.
"""
_SCAN_EDGE: Final = 2000
"""Measured: at the camera's full 4032 px Tesseract dropped the "51" it reads
at 1600-2500 px on the same page."""
_SURE_CONF: Final = 80.0
_SURE_LEN: Final = 3
_WIDE: Final = 1.5
_TSV_FIELDS: Final = 12
_ROTATIONS: Final = (0, 90, 180, 270)


@dataclass(frozen=True)
class Word:
    """One word Tesseract read, in the upright image's pixels."""

    text: str
    conf: float
    box: tuple[int, int, int, int]
    """left, top, right, bottom."""
    line: tuple[str, str, str]
    """block, paragraph, line: words sharing it share a printed line."""


@dataclass(frozen=True)
class Scan:
    """One photo, upright and read.

    ``size`` and the word boxes are in the scanned (downscaled) page;
    ``image`` is the full-resolution upright page.
    """

    rotation: int
    """Degrees counter-clockwise applied after EXIF to make it upright."""
    size: tuple[int, int]
    words: tuple[Word, ...]
    text: str
    image: Image.Image = field(compare=False, repr=False)
    """The upright grayscale page, for reading a boxed page number."""


def _run(argv: list[str], stdin: bytes = b"") -> str:
    """A tool's stdout, or "" (logged) if it failed or timed out."""
    try:
        done = subprocess.run(
            argv, input=stdin, capture_output=True, timeout=_TIMEOUT, check=False
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        _logger.warning("%s failed (%s)", argv[0], exc)
        return ""
    return done.stdout.decode("utf-8", errors="replace")


def tesseract(image: Image.Image, *args: str) -> str:
    """Tesseract's output for ``image`` (fed as PNG on stdin), or ""."""
    binary = shutil.which("tesseract")
    if binary is None:
        return ""
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return _run([binary, "stdin", "-", *args], buffer.getvalue())


def flatten(gray: Image.Image) -> Image.Image:
    """Ink on white, whatever the lighting.

    Subtract the page's own blurred background, then stretch. A phone photo
    of a curved page is darker towards the spine; on the measured photo this
    doubled the words read with confidence and reached the last line instead
    of stopping halfway.
    """
    background = gray.filter(ImageFilter.GaussianBlur(_BACKGROUND_BLUR))
    ink = ImageChops.subtract(background, gray)
    return Image.eval(ink, lambda v: 255 - min(255, v * _INK_GAIN))


def words(tsv: str) -> list[Word]:
    """Tesseract's ``tsv`` output as words; blanks and headers dropped."""
    found: list[Word] = []
    for row in tsv.splitlines()[1:]:
        cells = row.split("\t")
        if len(cells) != _TSV_FIELDS or not cells[11].strip():
            continue
        try:
            left, top, width, height = (int(c) for c in cells[6:10])
            conf = float(cells[10])
        except ValueError:
            _logger.warning("skipping a malformed Tesseract row: %.80s", row)
            continue
        found.append(
            Word(
                text=cells[11].strip(),
                conf=conf,
                box=(left, top, left + width, top + height),
                line=(cells[2], cells[3], cells[4]),
            )
        )
    return found


def _osd(gray: Image.Image) -> tuple[int, float]:
    """Tesseract's (rotation, confidence); (0, 0.0) if it has no opinion.

    "Rotate: N" means the page is turned N degrees counter-clockwise
    (calibrated on a known-upright page turned both ways).
    """
    out = tesseract(gray, "--psm", "0")
    rotate = re.search(r"Rotate: (\d+)", out)
    conf = re.search(r"Orientation confidence: ([\d.]+)", out)
    if rotate is None or conf is None:
        return 0, 0.0
    return int(rotate.group(1)), float(conf.group(1))


def _sure_words(gray: Image.Image) -> int:
    """Confident real words laid out horizontally -- high only when upright.

    Width matters: Tesseract reads a sideways page's vertical lines nearly
    as confidently as upright ones (79 vs 83 words on the p. 19 photo), but
    their word boxes come out taller than wide.
    """
    small = flatten(gray)
    small.thumbnail((_SCORE_EDGE, _SCORE_EDGE))
    return sum(
        1
        for w in words(tesseract(small, "-l", "pol", "--psm", "3", "tsv"))
        if w.conf >= _SURE_CONF
        and len(w.text) >= _SURE_LEN
        and w.text.isalpha()
        and w.box[2] - w.box[0] > _WIDE * (w.box[3] - w.box[1])
    )


def upright(gray: Image.Image) -> tuple[Image.Image, int]:
    """``gray`` turned so its text reads normally, and the angle used."""
    small = gray.copy()
    small.thumbnail((_OSD_EDGE, _OSD_EDGE))
    rotate, conf = _osd(small)
    if conf >= OSD_TRUST:
        angle = (360 - rotate) % 360
    else:
        scores = [(_sure_words(small.rotate(a, expand=True)), -a) for a in _ROTATIONS]
        angle = -max(scores)[1]  # ties go to the smallest turn
    return (gray.rotate(angle, expand=True) if angle else gray), angle


def page_text(found: list[Word]) -> str:
    """The words as printed lines, hyphen breaks rejoined, capped."""
    lines: dict[tuple[str, str, str], list[str]] = {}
    for word in found:
        lines.setdefault(word.line, []).append(word.text)
    raw = "\n".join(" ".join(line) for line in lines.values())
    return _HYPHEN_BREAK.sub(r"\1\2", raw)[:TEXT_LIMIT]


def open_gray(path: Path) -> Image.Image | None:
    """``path`` as grayscale, EXIF-turned, or ``None`` if unreadable."""
    try:
        with Image.open(path) as image:
            return ImageOps.exif_transpose(image).convert("L")
    except (OSError, UnidentifiedImageError) as exc:
        _logger.warning("cannot open %s for OCR (%s)", path.name, exc)
        return None


def scan(path: Path) -> Scan | None:
    """The photo upright, every word with its box, and the body text.

    ``None`` if the image cannot be opened or Tesseract is missing.
    """
    if shutil.which("tesseract") is None:
        return None
    gray = open_gray(path)
    if gray is None:
        return None
    turned, angle = upright(gray)
    small = turned.copy()
    small.thumbnail((_SCAN_EDGE, _SCAN_EDGE))
    found = words(tesseract(flatten(small), "-l", "pol", "--psm", "3", "tsv"))
    return Scan(
        rotation=angle,
        size=small.size,
        words=tuple(found),
        text=page_text(found),
        image=turned,
    )


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
