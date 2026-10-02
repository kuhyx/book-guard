# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_lookup: source order, merging, the cache, pacing and backoff."""

from __future__ import annotations

from dataclasses import replace
from datetime import UTC, datetime, timedelta
import json
from typing import TYPE_CHECKING

import pytest

from book_guard import _lookup
from book_guard._http import UnavailableError
from book_guard._openlibrary import BookInfo

if TYPE_CHECKING:
    from collections.abc import Callable

    from book_guard._paths import Paths

PL = "9788368380002"
EN = "9780735211292"
NOW = datetime(2026, 10, 2, 12, 0, tzinfo=UTC)
FULL = BookInfo("Cesarz", "Sheridan", 406, PL)


class Clock:
    def __init__(self) -> None:
        self.t = 1_000_000.0
        self.slept: list[float] = []

    def __call__(self) -> float:
        return self.t

    def sleep(self, seconds: float) -> None:
        self.slept.append(seconds)
        self.t += seconds


Answer = BookInfo | Exception | None


def _fake(monkeypatch: pytest.MonkeyPatch, answers: dict[str, Answer]) -> list[str]:
    """Each source answers a BookInfo, None, or raises the given exception."""
    asked: list[str] = []

    def make(name: str) -> Callable[[Paths, str], BookInfo | None]:
        def fetch(_paths: Paths, isbn: str) -> BookInfo | None:
            asked.append(name)
            answer = answers.get(name)
            if isinstance(answer, Exception):
                raise answer
            return None if answer is None else replace(answer, isbn=isbn)

        return fetch

    for name in list(_lookup.FETCHERS):
        monkeypatch.setitem(_lookup.FETCHERS, name, make(name))
    return asked


def _look(
    paths: Paths, isbn: str, clock: Clock, now: datetime = NOW
) -> BookInfo | None:
    return _lookup.lookup_book(paths, isbn, now=now, clock=clock, sleep=clock.sleep)


def test_source_order() -> None:
    assert _lookup.source_order(PL)[:2] == ["biblioteka-narodowa", "openlibrary"]
    assert _lookup.source_order("8375797383")[0] == "biblioteka-narodowa"
    assert _lookup.source_order(EN) == [
        "openlibrary",
        "biblioteka-narodowa",
        "e-isbn",
        "google-books",
    ]


def test_stops_once_title_author_and_pages_are_known(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    asked = _fake(monkeypatch, {"biblioteka-narodowa": FULL})
    assert _look(bg_paths, PL, Clock()) == FULL
    assert asked == ["biblioteka-narodowa"]


def test_fields_merge_across_sources(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    asked = _fake(
        monkeypatch,
        {
            "openlibrary": BookInfo("Atomic Habits", "", 320, EN),
            "biblioteka-narodowa": None,
            "e-isbn": BookInfo("Other title", "", None, EN),
            "google-books": BookInfo("", "James Clear", 300, EN),
        },
    )
    assert _look(bg_paths, EN, Clock()) == BookInfo(
        "Atomic Habits", "James Clear", 320, EN
    )
    assert len(asked) == 4


def test_complete_answer_is_cached_for_good(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    asked = _fake(monkeypatch, {"biblioteka-narodowa": FULL})
    _look(bg_paths, PL, Clock())
    later = NOW + timedelta(days=400)
    assert _look(bg_paths, PL, Clock(), later) == FULL
    assert asked == ["biblioteka-narodowa"]


def test_miss_is_cached_for_a_fortnight(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    asked = _fake(monkeypatch, {})
    assert _look(bg_paths, PL, Clock()) is None
    assert _look(bg_paths, PL, Clock(), NOW + timedelta(days=13)) is None
    assert len(asked) == 4
    assert _look(bg_paths, PL, Clock(), NOW + timedelta(days=15)) is None
    assert len(asked) == 8


def test_partial_answer_is_reused_until_recheck(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    partial = BookInfo("Cesarz", "Sheridan", None, PL)
    asked = _fake(monkeypatch, {"e-isbn": partial})
    assert _look(bg_paths, PL, Clock()) == partial
    assert _look(bg_paths, PL, Clock(), NOW + timedelta(days=1)) == partial
    assert len(asked) == 4


def test_refusal_is_not_cached_and_backs_off(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    clock = Clock()
    asked = _fake(monkeypatch, {"biblioteka-narodowa": UnavailableError("429")})
    assert _look(bg_paths, PL, clock) is None
    assert not bg_paths.isbn_cache.exists()
    clock.t += 60
    _look(bg_paths, PL, clock)
    # Backing off: the refusing source is not asked again within the hour.
    assert asked.count("biblioteka-narodowa") == 1
    clock.t += _lookup.BACKOFF_FIRST
    _look(bg_paths, PL, clock)
    assert asked.count("biblioteka-narodowa") == 2
    state = _lookup._load(bg_paths.lookup_sources)
    assert state["biblioteka-narodowa"]["backoff"] == 2 * _lookup.BACKOFF_FIRST


def test_backoff_is_capped_and_clears_on_success(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    clock = Clock()
    answers: dict[str, Answer] = {"biblioteka-narodowa": ValueError("bad json")}
    _fake(monkeypatch, answers)
    for _ in range(8):
        _look(bg_paths, PL, clock)
        clock.t += _lookup.BACKOFF_MAX
    state = _lookup._load(bg_paths.lookup_sources)
    assert state["biblioteka-narodowa"]["backoff"] == _lookup.BACKOFF_MAX
    answers["biblioteka-narodowa"] = FULL
    assert _look(bg_paths, PL, clock) == FULL
    state = _lookup._load(bg_paths.lookup_sources)
    assert state["biblioteka-narodowa"]["backoff"] == 0


def test_nobody_answering_raises(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _fake(monkeypatch, dict.fromkeys(_lookup.FETCHERS, OSError("down")))
    with pytest.raises(UnavailableError, match="no book source answered"):
        _look(bg_paths, PL, Clock())


def test_requests_to_one_source_are_paced(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    clock = Clock()
    _fake(monkeypatch, {"biblioteka-narodowa": FULL})
    _look(bg_paths, PL, clock)
    clock.t += 0.5
    _look(bg_paths, "9788375797381", clock)
    assert clock.slept == [pytest.approx(_lookup.MIN_GAP - 0.5)]


def test_unreadable_state_starts_afresh(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    bg_paths.data_dir.mkdir(parents=True, exist_ok=True)
    bg_paths.isbn_cache.write_text("{not json", encoding="utf-8")
    bg_paths.lookup_sources.write_text("[1, 2]", encoding="utf-8")
    _fake(monkeypatch, {"biblioteka-narodowa": FULL})
    assert _look(bg_paths, PL, Clock()) == FULL
    bg_paths.isbn_cache.write_text(json.dumps({PL: "junk"}), encoding="utf-8")
    assert _look(bg_paths, PL, Clock()) == FULL


def test_cache_entry_with_odd_fields(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    bg_paths.data_dir.mkdir(parents=True, exist_ok=True)
    entry = {"title": "T", "pages": "406", "checked_at": NOW.isoformat()}
    bg_paths.isbn_cache.write_text(json.dumps({PL: entry}), encoding="utf-8")
    asked = _fake(monkeypatch, {})
    assert _look(bg_paths, PL, Clock()) == BookInfo("T", "", None, PL)
    assert asked == []


def test_google_uses_the_key_file(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    keys: list[str] = []

    def google(_isbn: str, key: str) -> None:
        keys.append(key)

    monkeypatch.setattr(_lookup, "google_books", google)
    assert _lookup._google(bg_paths, PL) is None
    bg_paths.data_dir.mkdir(parents=True, exist_ok=True)
    bg_paths.google_key_file.write_text(" k3y\n", encoding="utf-8")
    _lookup._google(bg_paths, PL)
    assert keys == ["", "k3y"]


def test_default_fetchers_reach_the_source_modules(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(_lookup, "biblioteka_narodowa", lambda isbn: FULL)
    monkeypatch.setattr(_lookup, "lookup_isbn", lambda isbn: None)
    monkeypatch.setattr(_lookup, "e_isbn", lambda isbn: None)
    assert _lookup.FETCHERS["biblioteka-narodowa"](bg_paths, PL) == FULL
    assert _lookup.FETCHERS["openlibrary"](bg_paths, PL) is None
    assert _lookup.FETCHERS["e-isbn"](bg_paths, PL) is None
