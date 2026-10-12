# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""From the switch the hour is the day's requirement, summed across sessions."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from typing import TYPE_CHECKING

from book_guard import _bonus, _ledger, _quiz
from book_guard._ledger import CREDIT, Entry
from book_guard._quiz import Verdict
from book_guard.tests._flow_helpers import add_credit, make_book, only_session, rec

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths

TUE = date(2026, 10, 13)
"""Nothing read: Tue asks 15/565 of the 645.8 left at the switch = 18."""
EVENING = datetime(2026, 10, 13, 16, 0, tzinfo=UTC)


def _record(paths: Paths, pages: int, tag: str = "s", *, minutes: int = 60) -> str:
    """Credit a session of ``pages`` pages read on TUE; return its bonus flag."""
    start = EVENING + timedelta(minutes=len(tag) * 90)
    session = only_session(
        [
            rec(f"{tag}-start", 10, start),
            rec(f"{tag}-end", 10 + pages, start + timedelta(minutes=minutes)),
        ]
    )
    entry = _quiz.record_verdict(paths, make_book(), session, Verdict(True, "f"), "s")
    assert entry is not None
    assert entry.day == TUE.isoformat()
    return entry.detail["bonus"]


def _ledger_of(paths: Paths) -> _ledger.Ledger:
    return _ledger.load(paths.ledger, paths.key_file)


def test_the_requirement_is_fixed_by_earlier_days(bg_paths: Paths) -> None:
    assert _bonus.day_requirement(_ledger_of(bg_paths), TUE) == 18
    add_credit(bg_paths, TUE.isoformat(), 40)  # today's pages do not move it
    assert _bonus.day_requirement(_ledger_of(bg_paths), TUE) == 18


def test_one_session_reaching_the_requirement_earns(bg_paths: Paths) -> None:
    assert _record(bg_paths, 18, minutes=20) == "1"


def test_one_page_short_earns_nothing(bg_paths: Paths) -> None:
    assert _record(bg_paths, 17) == "0"


def test_sessions_add_up_and_only_the_crossing_one_earns(bg_paths: Paths) -> None:
    assert _record(bg_paths, 10, "a") == "0"
    assert _record(bg_paths, 8, "bb", minutes=8) == "1"
    # One bonus a day: the next session is past the line but earns nothing.
    assert _record(bg_paths, 30, "ccc") == "0"
    flags = [e.detail["bonus"] for e in _ledger_of(bg_paths).of_kind(CREDIT)]
    assert flags == ["0", "1", "0"]


def test_the_old_session_bar_no_longer_applies(bg_paths: Paths) -> None:
    # 15 pages / 15 min earned the hour before the switch; now 18 are asked.
    assert _record(bg_paths, 15, minutes=15) == "0"


def test_a_page_less_row_never_earns(bg_paths: Paths) -> None:
    empty = Entry("zero", CREDIT, TUE.isoformat(), 0)
    assert not _bonus.reaches_requirement(_ledger_of(bg_paths), empty)


def test_a_free_day_earns_with_any_reading(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("freedays.is_free_day", lambda day=None, **_k: day == TUE)
    assert _bonus.day_requirement(_ledger_of(bg_paths), TUE) == 0
    assert _record(bg_paths, 1) == "1"


def _row(paths: Paths, entry_id: str, day: str, pages: int) -> None:
    detail = {"pages": str(pages), "minutes": "30", "bonus": "0", "ended_at": "5"}
    _ledger.append(
        paths.ledger, paths.key_file, Entry(entry_id, CREDIT, day, pages, detail)
    )


def test_regrant_judges_post_switch_days_by_the_requirement(bg_paths: Paths) -> None:
    _row(bg_paths, "short", TUE.isoformat(), 10)
    assert _bonus.regrant(bg_paths, dry_run=True) == []
    # A late-graded 600 pages on Monday put the reader 211.5 past the line,
    # taken evenly off the 14 Mon-Fri days left: Tuesday now asks 3, and its
    # 10 earn the hour through a zero-page row.
    _row(bg_paths, "monday", "2026-10-12", 600)
    grants = _bonus.regrant(bg_paths)
    assert [(g.day, g.detail["grant_of"]) for g in grants] == [
        (TUE.isoformat(), "short"),
        ("2026-10-12", "monday"),
    ]
    assert _bonus.regrant(bg_paths) == []
