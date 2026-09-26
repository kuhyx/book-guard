# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_anchor: locating a session's photos in the indexed book text."""

from __future__ import annotations

import hashlib
from typing import TYPE_CHECKING

import pytest

from book_guard import _anchor, _embed
from book_guard._anchor import MIN_SCORE, Span
from book_guard._bookindex import Hit
from book_guard._photos import PhotoRecord
from book_guard._sessions import Session

if TYPE_CHECKING:
    from book_guard._paths import Paths


def _bucket(word: str) -> int:
    return hashlib.sha256(word.encode()).digest()[0] % 64


def _distinct_words(count: int) -> list[str]:
    """Words the fake embedder puts in pairwise-different dimensions."""
    words: list[str] = []
    used: set[int] = set()
    i = 0
    while len(words) < count:
        word = f"w{i}"
        if _bucket(word) not in used:
            used.add(_bucket(word))
            words.append(word)
        i += 1
    return words


WORDS = _distinct_words(5)
SECTION = 1400  # two full windows of a single word per section


def _section(word: str) -> str:
    return (f"{word} " * (SECTION // (len(word) + 1) + 1))[:SECTION]


BOOK = "".join(_section(w) for w in WORDS[:4])


def _photo(sha: str, page: int, text: str, minute: int) -> PhotoRecord:
    taken = f"2026-10-02T10:{minute:02d}:00+00:00"
    return PhotoRecord(
        sha=sha * 16,
        name=sha,
        taken_at=taken,
        uploaded_at=taken,
        kind="page",
        page=page,
        text=text,
    )


def _session(
    start: str, end: str, *, pages: int = 10, check: str | None = None
) -> Session:
    first = _photo("a", 1, start, 0)
    last = _photo("b", 1 + pages, end, 59)
    proof = _photo("c", 3, check, 59) if check is not None else None
    return Session(first, last, 3, proof)


def _query(word: str) -> str:
    return f"{word} " * 30


@pytest.fixture
def indexed(bg_paths: Paths) -> Paths:
    _embed.build(bg_paths, "978", BOOK, source="book.txt")
    return bg_paths


def test_no_isbn_or_no_index(bg_paths: Paths) -> None:
    session = _session(_query(WORDS[0]), _query(WORDS[2]))
    for isbn in ("", "missing"):
        span = _anchor.find_span(bg_paths, isbn, session)
        assert span == Span("", (), "no book file attached")
        assert not span.usable


def test_short_text_refused(indexed: Paths) -> None:
    span = _anchor.find_span(indexed, "978", _session(_query(WORDS[0]), "  tiny  "))
    assert "too little legible text" in span.reason
    assert not span.usable


def test_no_consistent_chain(indexed: Paths) -> None:
    span = _anchor.find_span(
        indexed, "978", _session(_query(WORDS[4]), _query(WORDS[4]))
    )
    assert not span.usable
    assert span.reason.startswith("no consistent anchors")
    assert span.scores == (0.0, 0.0)


def test_anchored_span(indexed: Paths) -> None:
    session = _session(_query(WORDS[0]), _query(WORDS[2]), check=_query(WORDS[1]))
    span = _anchor.find_span(indexed, "978", session)
    assert span.usable
    assert span.reason == "anchored"
    assert span.scores == (1.0, 1.0, 1.0)
    tokens = set(span.text.split())
    assert {WORDS[0], WORDS[1], WORDS[2]} <= tokens
    assert WORDS[3] not in tokens


def test_zero_page_session_still_gets_a_span_limit(indexed: Paths) -> None:
    session = _session(_query(WORDS[0]), _query(WORDS[0]), pages=0)
    span = _anchor.find_span(indexed, "978", session)
    assert span.usable
    tokens = set(span.text.split())
    assert WORDS[0] in tokens
    assert not tokens & set(WORDS[1:])


def test_span_capped(indexed: Paths, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(_anchor, "MAX_SPAN_CHARS", 50)
    span = _anchor.find_span(
        indexed, "978", _session(_query(WORDS[0]), _query(WORDS[3]))
    )
    assert len(span.text) == 50


def _hit(start: int, score: float, length: int = 10) -> Hit:
    return Hit(start, start + length, score)


def test_best_chain_prefers_highest_in_order_sum() -> None:
    start = [_hit(500, 0.95), _hit(100, 0.9)]
    end = [_hit(50, 0.99), _hit(200, 0.8), _hit(150, 0.7)]
    chain = _anchor.best_chain([start, end], 10_000)
    assert chain == (_hit(100, 0.9), _hit(200, 0.8))


def test_best_chain_rejects_weak_scores() -> None:
    assert _anchor.best_chain([[_hit(0, MIN_SCORE - 0.01)]], 10_000) is None
    assert _anchor.best_chain([[_hit(0, MIN_SCORE)]], 10_000) == (_hit(0, MIN_SCORE),)


def test_best_chain_span_limit() -> None:
    candidates = [[_hit(0, 0.9)], [_hit(1000, 0.9), _hit(20, 0.6)]]
    assert _anchor.best_chain(candidates, 1010) == (_hit(0, 0.9), _hit(1000, 0.9))
    assert _anchor.best_chain(candidates, 1009) == (_hit(0, 0.9), _hit(20, 0.6))
    assert _anchor.best_chain(candidates, 29) is None


def test_best_chain_equal_starts_are_in_order() -> None:
    chain = _anchor.best_chain([[_hit(5, 0.7)], [_hit(5, 0.7)]], 100)
    assert chain == (_hit(5, 0.7), _hit(5, 0.7))
