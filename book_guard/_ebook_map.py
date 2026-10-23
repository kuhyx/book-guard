# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Where the paper copy's pages fall in the attached ebook's text.

In-app reading is credited in *physical* pages of the registered copy, but
the ebook is often another edition or translation (Zbrodnia i kara: a 1928
Wikisource text against a modern paper translation), so its offsets mean
nothing on their own. The pages the reader has photographed are the bridge:
each photo's transcription is located in the ebook text
(:mod:`book_guard._ebook_locate`), and the page map is piecewise linear
through those knots plus the story's two ends
(:mod:`book_guard._ebook_text`) -- an *estimate*, shown as such ("≈ p. 312")
everywhere it surfaces.

Pure: text and (page, transcription) pairs in, a :class:`PageMap` out.
"""

from __future__ import annotations

import bisect
from dataclasses import dataclass
from itertools import pairwise
import logging
import math
from typing import TYPE_CHECKING, Any, Final

import numpy as np

from book_guard._ebook_locate import Knot, StemIndex, knots_from, locate
from book_guard._ebook_text import story_bounds

if TYPE_CHECKING:
    from collections.abc import Sequence

_logger: Final = logging.getLogger(__name__)

MIN_MAP_KNOTS: Final = 2
"""A map needs two knots to interpolate between."""
MIN_KNOTS: Final = 3
"""Located pages needed before any page is estimated."""
SCHEMA: Final = 1


def page_coordinate(knots: Sequence[Knot], offset: float) -> float:
    """The continuous page at ``offset``: linear between knots, flat outside.

    The app's Dart port computes this with the same arithmetic, in the same
    order, so both floor to the same page (fixture-checked).
    """
    if offset <= knots[0].offset:
        return knots[0].page
    if offset >= knots[-1].offset:
        return knots[-1].page
    i = bisect.bisect_right([k.offset for k in knots], offset)
    a, b = knots[i - 1], knots[i]
    return a.page + (b.page - a.page) * (offset - a.offset) / (b.offset - a.offset)


@dataclass(frozen=True)
class PageMap:
    """The estimated physical page of every ebook offset.

    Attributes:
        knots: Photo knots plus the story's two ends, strictly rising.
        start: Where the story starts in the text.
        end: Where it ends (back matter after it).
        last_page: The registered copy's last page, if known.
        photos: How many photographed pages the map rests on.
        residuals: Leave-one-out error of each inner photo knot, in pages.
        slope: Characters per page, least squares over the photo knots.
    """

    knots: tuple[Knot, ...]
    start: int
    end: int
    last_page: int | None
    photos: int
    residuals: tuple[float, ...]
    slope: float

    def page_at(self, offset: int) -> int:
        """The physical page ``offset`` falls on (``last_page + 1`` at the end).

        Reading from offset ``a`` to ``b`` covers ``page_at(b) - page_at(a)``
        pages -- the stop page is not read, exactly as with photos.
        """
        return max(1, math.floor(page_coordinate(self.knots, offset)))

    def shown_page(self, offset: int) -> int:
        """The page to show the reader: never past the book's last page."""
        page = self.page_at(offset)
        return min(page, self.last_page) if self.last_page else page

    def offset_at(self, page: int) -> int:
        """An offset on ``page`` (its middle); the nearest end outside the map."""
        target = page + 0.5
        if target <= self.knots[0].page:
            return self.knots[0].offset
        if target >= self.knots[-1].page:
            return self.knots[-1].offset
        i = bisect.bisect_right([k.page for k in self.knots], target)
        a, b = self.knots[i - 1], self.knots[i]
        return math.floor(
            a.offset + (b.offset - a.offset) * (target - a.page) / (b.page - a.page)
        )

    def to_json(self) -> dict[str, Any]:
        """The served form (``Reading/ebooks/<isbn>.map.json``'s core)."""
        return {
            "schema": SCHEMA,
            "knots": [[k.offset, k.page] for k in self.knots],
            "start": self.start,
            "end": self.end,
            "last_page": self.last_page,
            "photos": self.photos,
            "residuals": list(self.residuals),
            "slope": self.slope,
        }

    @staticmethod
    def from_json(raw: object) -> PageMap | None:
        """A map written by :meth:`to_json`, or None when it is not one."""
        if not isinstance(raw, dict):
            return None
        try:
            last = raw["last_page"]
            page_map = PageMap(
                knots=tuple(Knot(int(o), float(p)) for o, p in raw["knots"]),
                start=int(raw["start"]),
                end=int(raw["end"]),
                last_page=None if last is None else int(last),
                photos=int(raw["photos"]),
                residuals=tuple(float(r) for r in raw["residuals"]),
                slope=float(raw["slope"]),
            )
        except (KeyError, TypeError, ValueError) as exc:
            _logger.warning("not a page map (%s: %s)", type(exc).__name__, exc)
            return None
        knots = page_map.knots
        rising = all(
            a.offset < b.offset and a.page < b.page for a, b in pairwise(knots)
        )
        return page_map if len(knots) >= MIN_MAP_KNOTS and rising else None


def _loo_residuals(knots: tuple[Knot, ...], slope: float) -> tuple[float, ...]:
    """Each inner knot predicted from the others, its error in pages."""
    out = []
    for i in range(1, len(knots) - 1):
        rest = knots[:i] + knots[i + 1 :]
        predicted = np.interp(
            knots[i].page, [k.page for k in rest], [k.offset for k in rest]
        )
        out.append(round((knots[i].offset - float(predicted)) / slope, 2))
    return tuple(out)


def build_map(
    text: str, photos: Sequence[tuple[int, str]], last_page: int | None
) -> PageMap | None:
    """The page map from ``photos`` (``(page, transcription)``), or None.

    None when fewer than :data:`MIN_KNOTS` pages locate in order. The
    story's start is
    extrapolated back from the first photo at the fitted characters per
    page (never below page 1); its end is the end of ``last_page`` when the
    copy's last page is known, else extrapolated the same way.
    """
    index = StemIndex(text)
    located = [
        (page, *found)
        for page, words in photos
        if (found := locate(index, words)) is not None
    ]
    knots = knots_from(located)
    if len(knots) < MIN_KNOTS:
        return None
    slope = float(np.polyfit([k.page for k in knots], [k.offset for k in knots], 1)[0])
    start, end = story_bounds(text)
    first, last = knots[0], knots[-1]
    # A story found to start after the first photo (it opens with short
    # dialogue lines) or to end before the last (a photographed afterword)
    # falls back to the whole text; a located middle is never at either
    # edge, so both end knots always exist.
    start = start if start < first.offset else 0
    end = end if end > last.offset else len(text)
    head = Knot(start, max(1.0, first.page - (first.offset - start) / slope))
    tail = Knot(
        end,
        float(last_page + 1)
        if last_page and last_page + 1 > last.page
        else last.page + (end - last.offset) / slope,
    )
    return PageMap(
        knots=(head, *knots, tail),
        start=start,
        end=end,
        last_page=last_page,
        photos=len(knots),
        residuals=_loo_residuals(knots, slope),
        slope=round(slope, 3),
    )
