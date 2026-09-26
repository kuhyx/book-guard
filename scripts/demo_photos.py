# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Render fake "phone photos" of book pages, with EXIF capture times.

For demos and manual end-to-end runs only (never used by the gate): the text
comes from a real epub so the vision call and the grader see real prose, and
the EXIF DateTimeOriginal is set so the session clock can be exercised.

    python3 scripts/demo_photos.py BOOK.epub OUT_DIR PAGE ISO_TIME [PAGE ISO_TIME ...]
"""

from __future__ import annotations

from datetime import datetime
import html
from pathlib import Path
import re
import sys
import textwrap
import zipfile

from PIL import Image, ImageDraw, ImageFont

_FONT = "/usr/share/fonts/TTF/DejaVuSerif.ttf"
_CHARS_PER_PAGE = 1500
_EXIF_IFD = 0x8769
_TAG = re.compile(r"<[^>]+>")


def _out(*parts: object) -> None:
    """A report line on stdout (a script's output, not a log)."""
    sys.stdout.write(" ".join(str(x) for x in parts) + "\n")


def book_text(epub: Path) -> str:
    """All body text of an epub, in spine-ish (file name) order."""
    with zipfile.ZipFile(epub) as archive:
        names = sorted(n for n in archive.namelist() if n.endswith((".xhtml", ".html")))
        raw = " ".join(archive.read(n).decode("utf-8", "replace") for n in names)
    body = html.unescape(_TAG.sub(" ", raw))
    return re.sub(r"\s+", " ", body).strip()


def render_page(text: str, page: int, taken: datetime, out: Path) -> None:
    """One page photo: wrapped text, a centred page number, an EXIF time."""
    chunk = text[page * _CHARS_PER_PAGE : (page + 1) * _CHARS_PER_PAGE]
    image = Image.new("RGB", (1000, 1450), (246, 241, 228))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(_FONT, 24)
    draw.multiline_text(
        (70, 80), textwrap.fill(chunk, 62), fill="black", font=font, spacing=10
    )
    draw.text((490, 1370), str(page), fill="black", font=font)
    exif = Image.Exif()
    exif.get_ifd(_EXIF_IFD)[0x9003] = taken.strftime("%Y:%m:%d %H:%M:%S")
    exif.get_ifd(_EXIF_IFD)[0x9011] = (
        taken.strftime("%z")[:3] + ":" + taken.strftime("%z")[3:]
    )
    image.save(out, "JPEG", quality=85, exif=exif)


def main(argv: list[str]) -> int:
    """Render each PAGE/ISO_TIME pair into OUT_DIR."""
    epub, out_dir, *pairs = argv
    text = book_text(Path(epub))
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    for page, iso in zip(pairs[::2], pairs[1::2], strict=True):
        taken = datetime.fromisoformat(iso).astimezone()
        target = Path(out_dir) / f"PXL_{taken:%Y%m%d_%H%M%S}_p{page}.jpg"
        render_page(text, int(page), taken, target)
        _out(target)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
