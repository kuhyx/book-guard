# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Who earns the day's reading hour: the size bars, the pace bar, regrant."""

from __future__ import annotations

from datetime import timedelta
from typing import TYPE_CHECKING

import pytest

from book_guard import _bonus, _cli, _ledger, _quiz
from book_guard._ledger import CREDIT, Entry
from book_guard._quiz import Verdict
from book_guard.tests._flow_helpers import (
    T0,
    add_credit,
    make_book,
    only_session,
    rec,
)

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._sessions import Session

DAY = "2026-10-05"
"""The day of :data:`T0`; three counted days precede it, so the line is ahead."""


def _session(pages: int, minutes: int) -> Session:
    """A session of exactly ``pages`` pages and ``minutes`` minutes on DAY."""
    return only_session(
        [rec("s", 10, T0), rec("e", 10 + pages, T0 + timedelta(minutes=minutes))]
    )


def _on_pace(paths: Paths) -> None:
    add_credit(paths, "2026-10-04", 600)


def _bonus_of(paths: Paths, session: Session, *, passed: bool = True) -> str:
    entry = _quiz.record_verdict(paths, make_book(), session, Verdict(passed, "f"), "s")
    assert entry is not None
    return entry.detail["bonus"]


@pytest.mark.parametrize(
    ("pages", "minutes", "pace", "expected"),
    [
        (15, 15, False, True),
        (14, 15, False, False),
        (15, 14, False, False),
        (10, 10, True, True),
        (9, 10, True, False),
        (10, 9, True, False),
    ],
)
def test_qualifies_bars(
    pages: int, minutes: int, *, pace: bool, expected: bool
) -> None:
    assert _bonus.qualifies(pages, minutes, on_pace=pace) is expected


def test_bonus_eligible_wraps_the_bars() -> None:
    session = _session(10, 10)
    assert not _quiz.bonus_eligible(session)
    assert _quiz.bonus_eligible(session, on_pace=True)


def test_on_pace_counts_the_credit_and_ignores_later_days(bg_paths: Paths) -> None:
    credit = Entry("c", CREDIT, DAY, 10)
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert not _bonus.is_on_pace(ledger, credit)
    add_credit(bg_paths, "2026-10-20", 600)
    later = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert not _bonus.is_on_pace(later, credit)
    _on_pace(bg_paths)
    assert _bonus.is_on_pace(_ledger.load(bg_paths.ledger, bg_paths.key_file), credit)


def test_just_under_both_bars_earns_nothing(bg_paths: Paths) -> None:
    assert _bonus_of(bg_paths, _session(14, 14)) == "0"


def test_small_session_off_pace_earns_nothing(
    bg_paths: Paths,
) -> None:
    assert _bonus_of(bg_paths, _session(10, 10)) == "0"


def test_big_session_off_pace_earns(bg_paths: Paths) -> None:
    assert _bonus_of(bg_paths, _session(15, 15)) == "1"


def test_small_session_on_pace_earns(bg_paths: Paths) -> None:
    _on_pace(bg_paths)
    assert _bonus_of(bg_paths, _session(10, 10)) == "1"


def test_tiny_session_on_pace_earns_nothing(bg_paths: Paths) -> None:
    _on_pace(bg_paths)
    assert _bonus_of(bg_paths, _session(9, 9)) == "0"


def test_failed_quiz_never_earns(bg_paths: Paths) -> None:
    _on_pace(bg_paths)
    assert _bonus_of(bg_paths, _session(40, 40), passed=False) == "0"


def _credit(paths: Paths, entry_id: str, day: str, **detail: str) -> None:
    row = {"pages": "12", "minutes": "12", "bonus": "0", "ended_at": "5", **detail}
    _ledger.append(
        paths.ledger,
        paths.key_file,
        Entry(entry_id, CREDIT, day, int(row["pages"] or 0), row),
    )


def _rows(paths: Paths) -> list[Entry]:
    return _ledger.load(paths.ledger, paths.key_file).of_kind(CREDIT)


def test_regrant_writes_one_zero_page_row_once(bg_paths: Paths) -> None:
    _on_pace(bg_paths)
    _credit(bg_paths, "s1", DAY, graded="0")
    dry = _bonus.regrant(bg_paths, dry_run=True)
    assert [g.entry_id for g in dry] == ["bonus:s1"]
    assert len(_rows(bg_paths)) == 2
    (grant,) = _bonus.regrant(bg_paths)
    assert (grant.amount, grant.day) == (0, DAY)
    assert grant.detail["bonus"] == "1"
    assert grant.detail["grant_of"] == "s1"
    assert grant.detail["ended_at"] == "5"
    assert grant.detail["graded"] == "0"
    assert len(_rows(bg_paths)) == 3
    assert _bonus.regrant(bg_paths) == []
    assert len(_rows(bg_paths)) == 3


def test_regrant_skips_what_cannot_or_need_not_earn(bg_paths: Paths) -> None:
    _credit(bg_paths, "behind", DAY, pages="12", minutes="12")
    _credit(bg_paths, "no-minutes", "2026-10-06", minutes="")
    _credit(bg_paths, "has-bonus", "2026-10-07", pages="40", minutes="40", bonus="1")
    _credit(bg_paths, "same-day", "2026-10-07", pages="40", minutes="40")
    assert _bonus.regrant(bg_paths) == []


def test_regrant_command(bg_paths: Paths, capsys: pytest.CaptureFixture[str]) -> None:
    _on_pace(bg_paths)
    _credit(bg_paths, "s1", DAY)
    assert _cli.main(["regrant", "--dry-run"]) == 0
    assert f"would grant {DAY} bonus for s1" in capsys.readouterr().out
    assert len(_rows(bg_paths)) == 2
    assert _cli.main(["regrant"]) == 0
    assert f"granted {DAY} bonus for s1" in capsys.readouterr().out
    assert len(_rows(bg_paths)) == 3
