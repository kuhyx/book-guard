# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Find what was read: the book text between the start and end photos.

The paper edition's page numbers mean nothing in the digital file (another
edition, maybe another language), so the photos' *text* is the anchor: each
transcription is embedded and matched against the book's chunks. The
grader then reads the continuous text from the start anchor to the end
anchor -- exactly the stretch the reader claims -- instead of top-k snippets.

Each photo keeps its top :data:`CANDIDATES` matches, and the chosen anchors
are the best-scoring combination that makes sense:

* every anchor scores at least :data:`MIN_SCORE` (a weak match is a guess,
  e.g. a photo too blurry to transcribe);
* they are in reading order, start <= check <= end;
* the span is not absurdly longer than the page count claims.

When any check fails the grader falls back to judging from the photos and
its own knowledge of the book, and says so in its feedback.
"""

from __future__ import annotations

from dataclasses import dataclass
from itertools import pairwise, product
from typing import TYPE_CHECKING, Final

from book_guard._bookindex import load
from book_guard._embed import embed_queries

if TYPE_CHECKING:
    from book_guard._bookindex import Hit
    from book_guard._paths import Paths
    from book_guard._sessions import Session

MIN_ANCHOR_CHARS: Final = 80
"""A transcription shorter than this is too little text to locate."""

MIN_SCORE: Final = 0.55
"""Cosine floor for a trusted anchor (paraphrase-multilingual-MiniLM)."""

MAX_CHARS_PER_PAGE: Final = 5_000
"""A printed page holds ~1.5-3k characters; beyond this the span is wrong."""

MAX_SPAN_CHARS: Final = 150_000
"""What the grader is ever handed, whatever the page count."""

CANDIDATES: Final = 5
"""Top matches kept per photo: 5^3 = 125 chains, trivially cheap."""


@dataclass(frozen=True)
class Span:
    """The anchored stretch of the book, or why there is none."""

    text: str
    scores: tuple[float, ...]
    reason: str

    @property
    def usable(self) -> bool:
        """Whether the grader should read this span."""
        return bool(self.text)


def _refuse(reason: str, scores: tuple[float, ...] = ()) -> Span:
    return Span(text="", scores=scores, reason=reason)


def find_span(paths: Paths, isbn: str, session: Session) -> Span:
    """Anchor ``session``'s photos in the book file indexed for ``isbn``."""
    index = load(paths, isbn) if isbn else None
    if index is None:
        return _refuse("no book file attached")
    photos = session.evidence
    if any(len(p.text.strip()) < MIN_ANCHOR_CHARS for p in photos):
        return _refuse("a photographed page had too little legible text to anchor")
    queries = embed_queries(paths, [p.text for p in photos])
    candidates = index.search(queries, top=CANDIDATES)
    best = best_chain(candidates, max(1, session.pages) * MAX_CHARS_PER_PAGE)
    if best is None:
        top = tuple(round(c[0].score, 3) for c in candidates)
        return _refuse(f"no consistent anchors (top scores {top})", top)
    scores = tuple(round(h.score, 3) for h in best)
    begin, end = best[0].start, best[-1].end
    return Span(
        text=index.text[begin:end][:MAX_SPAN_CHARS], scores=scores, reason="anchored"
    )


def best_chain(candidates: list[list[Hit]], max_span: int) -> tuple[Hit, ...] | None:
    """The highest-scoring in-order choice of one candidate per photo.

    Every pick must clear :data:`MIN_SCORE`, the picks must be in reading
    order, and the whole span must fit ``max_span``. A photo whose top-1 lands
    in the wrong chapter (1 in 10 Polish pages, measured) is then outvoted by
    its own second or third candidate instead of sinking the whole span.
    """
    usable = [[h for h in c if h.score >= MIN_SCORE] for c in candidates]
    chains = [
        combo
        for combo in product(*usable)
        if all(a.start <= b.start for a, b in pairwise(combo))
        and combo[-1].end - combo[0].start <= max_span
    ]
    return max(chains, key=lambda combo: sum(h.score for h in combo), default=None)
