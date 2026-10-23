# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Locating a photographed page in the ebook text: the page map's knots.

Deliberately lexical, not semantic. Exact phrases fail across translations,
and the embedding search (``_anchor``) is tuned for a short grading span,
not a whole-book scan. What works (measured 2026-10-23 on 25 photos of
Zbrodnia i kara, every one located in order, z 11-19, leave-one-out RMS
0.84 pages): 5-letter stems of 4+ letter words, idf-weighted, scored in
overlapping 1800-character windows; the best window's neighbourhood
centroid is the page's middle.
"""

from __future__ import annotations

import bisect
from dataclasses import dataclass
import math
import re
from typing import TYPE_CHECKING, Final

import numpy as np

if TYPE_CHECKING:
    from collections.abc import Iterable

MIN_WINDOWS: Final = 2
"""Fewer windows have no spread: nothing stands out."""
WINDOW: Final = 1800
"""Characters scored at once: a little more than one printed page."""
STEP: Final = 300
STEM: Final = 5
"""Letters a word is cut to: survives Polish inflection and OCR endings."""
MIN_Z: Final = 6.0
"""How far above the average window a located photo must score (in SDs).
Real photos scored 11-19; a page of another book stays far below."""
MIN_QUERY_STEMS: Final = 10
"""A transcription with fewer known stems is too little to locate."""
NEIGHBOURS: Final = 2
"""Windows either side of the best one in the located centroid."""
_WORD: Final = re.compile(r"[^\W\d_]{4,}")


@dataclass(frozen=True)
class Knot:
    """One point of the map: a text offset and its continuous page.

    Page ``N`` covers ``[N, N + 1)``; a photographed page's middle is
    ``N + 0.5``.
    """

    offset: int
    page: float


class StemIndex:
    """Overlapping windows of an ebook, as sets of word stems, with idf."""

    def __init__(self, text: str) -> None:
        """Tokenise ``text`` once; windows are word ranges by offset."""
        found = [(m.start(), m.group().lower()[:STEM]) for m in _WORD.finditer(text)]
        positions = [p for p, _ in found]
        self.starts = list(range(0, max(1, len(text) - WINDOW + 1), STEP))
        self.length = len(text)
        windows: dict[str, list[int]] = {}
        for w, start in enumerate(self.starts):
            lo = bisect.bisect_left(positions, start)
            hi = bisect.bisect_left(positions, start + WINDOW)
            for stem in {s for _, s in found[lo:hi]}:
                windows.setdefault(stem, []).append(w)
        count = len(self.starts)
        self.windows = {k: np.asarray(v) for k, v in windows.items()}
        self.idf = {k: math.log(count / len(v)) for k, v in windows.items()}


def locate(index: StemIndex, transcription: str) -> tuple[float, float] | None:
    """Where ``transcription`` sits in the text: ``(offset, z)``, or None.

    ``offset`` is the middle of the matched text; ``z`` how many standard
    deviations its window scored above the average window. None when the
    transcription has too few known stems, or every window scores alike.
    """
    stems = {m.group().lower()[:STEM] for m in _WORD.finditer(transcription)}
    known = stems & index.idf.keys()
    if len(known) < MIN_QUERY_STEMS or len(index.starts) < MIN_WINDOWS:
        return None
    scores = np.zeros(len(index.starts))
    for stem in known:
        scores[index.windows[stem]] += index.idf[stem]
    spread = float(scores.std())
    if spread == 0:
        return None
    best = int(np.argmax(scores))
    lo, hi = max(0, best - NEIGHBOURS), min(len(scores), best + NEIGHBOURS + 1)
    middle = float(np.average(index.starts[lo:hi], weights=scores[lo:hi]))
    offset = min(middle + WINDOW / 2, float(index.length))
    return offset, (float(scores[best]) - float(scores.mean())) / spread


def knots_from(
    located: Iterable[tuple[int, float, float]], *, min_z: float = MIN_Z
) -> tuple[Knot, ...]:
    """The photo knots: strong matches only, one per page, in reading order.

    ``located`` is ``(page, offset, z)`` per photo. A page photographed more
    than once is averaged. A page matched in the wrong chapter breaks the
    order; the longest in-order chain (strongest on a tie) is kept rather
    than dropping knots one at a time.
    """
    by_page: dict[int, list[tuple[float, float]]] = {}
    for page, offset, z in located:
        if z >= min_z and page >= 1:
            by_page.setdefault(page, []).append((offset, z))
    points = [
        (
            page,
            sum(o for o, _ in by_page[page]) / len(by_page[page]),
            max(z for _, z in by_page[page]),
        )
        for page in sorted(by_page)
    ]
    return tuple(
        Knot(round(points[i][1]), points[i][0] + 0.5) for i in _longest_rising(points)
    )


def _longest_rising(points: list[tuple[int, float, float]]) -> list[int]:
    """Indexes of the longest chain whose offsets rise; ties: the larger z sum.

    ``points`` are ``(page, offset, z)`` in page order.
    """
    best: list[tuple[int, float, int]] = []  # (length, z sum, previous)
    for i, (_, offset, z) in enumerate(points):
        chain = (1, z, -1)
        for j in range(i):
            if points[j][1] < offset:
                length, total, _ = best[j]
                chain = max(chain, (length + 1, total + z, j))
        best.append(chain)
    tip = max(range(len(best)), key=lambda i: best[i][:2], default=-1)
    chosen: list[int] = []
    while tip >= 0:
        chosen.append(tip)
        tip = best[tip][2]
    return chosen[::-1]
