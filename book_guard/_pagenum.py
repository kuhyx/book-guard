# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The printed page number: found by position, chosen by plausibility, never guessed.

The PC's own reading, for photos that arrive with no number from the phone
(the phone's number is taken as is, see :mod:`book_guard._reader`).

A page number is a line holding nothing but 1-4 digits in the top or bottom
fifth of the upright page. A chapter-opening page has two such lines (the
chapter numeral and the page number), so position alone cannot choose --
on the 2026-10-02 retake the chapter "1" sat nearer the edge than "19".
What the photo is *for* chooses instead:

* a check photo must show the page that was asked for;
* a stop photo's page must lie past the open start;
* a start photo takes the number nearest where the last session ended.

Two candidates still standing is "unclear", never a pick: on a stop photo
the larger number would earn more credit. The app then lets the reader box
the number, and :func:`read_box` reads just that box (a lone small "7" that
Tesseract misses on the whole page reads cleanly from a tight crop).
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
import re
from typing import TYPE_CHECKING, Final

from PIL import Image, ImageOps

from book_guard._ocr import tesseract, words

if TYPE_CHECKING:
    from book_guard._ocr import Scan

Box = tuple[int, int, int, int]
"""left, top, right, bottom."""

_EDGE_BAND: Final = 0.2
_MIN_CONF: Final = 60.0
_NUMBER: Final = re.compile(r"\d{1,4}")
_ANY_PAGE: Final = 9999
FAR_FROM_LAST: Final = 20
"""A start more than this many pages from the last photographed page (same
book) is not taken on the PC's own reading: it is far likelier a chapter
numeral than a jump -- and a start too low is extra credit."""
_BOX_PAD: Final = 0.25
_ORIENTATION_TAG: Final = 0x0112
_TRANSPOSE: Final = {
    2: Image.Transpose.FLIP_LEFT_RIGHT,
    3: Image.Transpose.ROTATE_180,
    4: Image.Transpose.FLIP_TOP_BOTTOM,
    5: Image.Transpose.TRANSPOSE,
    6: Image.Transpose.ROTATE_270,
    7: Image.Transpose.TRANSVERSE,
    8: Image.Transpose.ROTATE_90,
}
"""EXIF orientation -> the transpose ``ImageOps.exif_transpose`` applies."""


@dataclass(frozen=True)
class Context:
    """What the photo was taken for, as far as the page number goes."""

    expected: int | None = None
    """A check photo: the page that was asked for."""
    after: int | None = None
    """A stop photo: the open session's start page."""
    near: int | None = None
    """A start photo: where the last session (same book) ended."""
    last_page: int | None = None
    """The book's last page, when known."""
    hint: int | None = None
    """What the phone read. When set it IS the page: ``_reader.read`` takes
    it without consulting anything below -- these rules are the fallback
    for photos the phone did not read."""


@dataclass(frozen=True)
class Choice:
    """The page number, or why there is none."""

    page: int | None
    reason: str = ""


def candidates(scan: Scan) -> list[int]:
    """Numbers alone on a line near the top or bottom edge, in reading order."""
    lines: dict[tuple[str, str, str], list[int]] = {}
    for index, word in enumerate(scan.words):
        lines.setdefault(word.line, []).append(index)
    height = scan.size[1]
    found: list[int] = []
    for members in lines.values():
        if len(members) != 1:
            continue
        word = scan.words[members[0]]
        if not _NUMBER.fullmatch(word.text) or word.conf < _MIN_CONF:
            continue
        middle = (word.box[1] + word.box[3]) / 2
        if min(middle, height - middle) <= height * _EDGE_BAND:
            found.append(int(word.text))
    return list(dict.fromkeys(found))


def _plausible(found: list[int], context: Context) -> list[int]:
    top = context.last_page or _ANY_PAGE
    keep = [n for n in dict.fromkeys(found) if 1 <= n <= top]
    if context.after is not None:
        keep = [n for n in keep if n > context.after]
    return keep


def _unclear(options: list[int]) -> Choice:
    listed = " or ".join(str(n) for n in options)
    return Choice(None, f"page number unclear ({listed})")


def _far(page: int, context: Context, *, boxed: bool) -> bool:
    near = context.near
    return (
        not boxed
        and near is not None
        and context.after is None
        and abs(page - near) > FAR_FROM_LAST
    )


def _among(options: list[int], context: Context, *, boxed: bool) -> Choice:
    """One of several plausible ``options`` -- or "unclear"."""
    if len(options) == 1:
        if _far(options[0], context, boxed=boxed):
            return Choice(
                None, f"page {options[0]} is far from p. {context.near}, the last one"
            )
        return Choice(options[0])
    near = context.near
    if near is not None and context.after is None:
        ranked = sorted(options, key=lambda n: abs(n - near))
        if abs(ranked[0] - near) < abs(ranked[1] - near):
            return Choice(ranked[0])
    return _unclear(options)


def choose(found: list[int], context: Context, *, boxed: bool = False) -> Choice:
    """The page among ``found`` that fits ``context`` -- or why none does.

    ``boxed``: the reader pointed at the number themselves, so a start far
    from the last page is believed.
    """
    if context.expected is not None:
        if context.expected in found:
            return Choice(context.expected)
        return Choice(None, f"page {context.expected} not found on the photo")
    options = _plausible(found, context)
    if options:
        return _among(options, context, boxed=boxed)
    if context.after is not None and found:
        return Choice(None, f"no page after {context.after} found on the photo")
    return Choice(None, "no page number found")


def upright_box(stored: Image.Image, box: Box, rotation: int) -> Box | None:
    """``box`` in the stored file's pixels -> the same box on the upright page.

    The phone sends boxes in the stored pixels so the two sides cannot
    disagree about orientation; the PC then applies the EXIF turn and its
    own content rotation, exactly as it did to the page.
    """
    mask = Image.new("1", stored.size, 0)
    mask.paste(1, box)
    method = _TRANSPOSE.get(int(stored.getexif().get(_ORIENTATION_TAG, 1)))
    if method is not None:
        mask = mask.transpose(method)
    if rotation:
        mask = mask.rotate(rotation, expand=True)
    return mask.getbbox()


_BOX_VARIANTS: Final = (("7", "eng"), ("7", "pol"), ("8", "pol"), ("6", "pol"))
"""psm x language. Measured 2026-10-03 on a real p. 85 crop: single settings
read 85, 86, 8 or 856 -- no one of them is right every time."""
_INK: Final = 128


def _crop(upright_gray: Image.Image, box: Box) -> Image.Image:
    """``box`` with a margin, contrast stretched."""
    left, top, right, bottom = box
    pad = int(max(right - left, bottom - top) * _BOX_PAD)
    return ImageOps.autocontrast(
        upright_gray.crop(
            (
                max(0, left - pad),
                max(0, top - pad),
                min(upright_gray.width, right + pad),
                min(upright_gray.height, bottom + pad),
            )
        ),
        cutoff=1,
    )


def read_box(upright_gray: Image.Image, box: Box) -> list[int]:
    """Every number Tesseract reads inside ``box``, most often read first.

    One reading is not evidence: the same crop of a printed "85" reads "86"
    under some settings. The crop is read plain and thresholded under each
    of :data:`_BOX_VARIANTS`; the caller decides what the spread means.
    """
    crop = _crop(upright_gray, box)
    inked = crop.point(lambda v: 255 if v > _INK else 0)
    digits_only = ("-c", "tessedit_char_whitelist=0123456789")
    seen: Counter[int] = Counter()
    for image in (crop, inked):
        for psm, lang in _BOX_VARIANTS:
            tsv = tesseract(image, "-l", lang, "--psm", psm, *digits_only, "tsv")
            joined = "".join(w.text for w in words(tsv) if w.conf >= _MIN_CONF)
            if _NUMBER.fullmatch(joined):
                seen[int(joined)] += 1
    return [number for number, _count in seen.most_common()]
