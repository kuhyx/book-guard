# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Read a page number pencilled in the margin: a pre-fill for the keypad.

Some pages carry no printed number (a chapter opener) and the reader
pencils one on. Tesseract reads no handwriting, so a small local digit
network does (:mod:`book_guard._pencil_find`; no LLM, no network).

The answer is **never** a page by itself: it only pre-fills a number pad the
user confirms with one tap. Call it after :func:`book_guard._reader.read`
found no printed number -- a page with a printed number needs no pencil
reading, and a facing page's contents column must not be mistaken for one.
``None`` is the answer to anything doubtful, a lone "1" most of all.
"""

from __future__ import annotations

from functools import cache
import statistics
from typing import TYPE_CHECKING

import numpy as np

from book_guard._margin import sure_words
from book_guard._ocr import scan
from book_guard._pencil_find import find_number
from book_guard._pencil_net import Net, load
from book_guard._sparse import reads_upright

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._ocr import Scan, Word


_COLUMN_GAP = 1.0
"""Text columns more than this many lines apart are different pages."""


def column_body(page: Scan) -> tuple[tuple[int, int, int, int], float]:
    """The box and line height of the text column with the most words.

    An open book photographs the facing page too, and its text (or running
    head) must not stretch the body over the margin the number sits in.
    """
    scale = page.image.width / page.size[0]
    sure = sorted(sure_words(page.words), key=lambda w: w.box[0])
    line = scale * statistics.median(w.box[3] - w.box[1] for w in sure)
    columns: list[list[Word]] = []
    reach = 0.0
    for word in sure:
        right = word.box[2] * scale
        if columns and word.box[0] * scale <= reach + _COLUMN_GAP * line:
            columns[-1].append(word)
            reach = max(reach, right)
        else:
            columns.append([word])
            reach = right
    main = max(columns, key=len)
    box = (
        round(min(w.box[0] for w in main) * scale),
        round(min(w.box[1] for w in main) * scale),
        round(max(w.box[2] for w in main) * scale),
        round(max(w.box[3] for w in main) * scale),
    )
    return box, line


@cache
def _net() -> Net:
    return load()


def read_pencil_page(page: Scan) -> int | None:
    """The pencilled number in an already scanned page's margin, or ``None``."""
    if not reads_upright(page):
        return None  # the turn is unknown: a digit net cannot tell 6 from 9
    body, line = column_body(page)
    gray = np.asarray(page.image.convert("L"))
    return find_number(_net(), gray, body, line)


def read_pencil(path: Path) -> int | None:
    """The pencilled number on the photo at ``path``, or ``None``."""
    page = scan(path)
    return None if page is None else read_pencil_page(page)
