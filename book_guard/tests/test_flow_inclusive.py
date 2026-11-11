# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""backfill-inclusive: one signed +1 top-up per session counted the old way."""

from __future__ import annotations

from datetime import timedelta
from typing import TYPE_CHECKING

from book_guard import _cli, _inclusive, _ledger, _quiz
from book_guard._ledger import CREDIT, REJECT, Entry
from book_guard._pace_inputs import credits_by_day
from book_guard._quiz import Verdict
from book_guard.tests._flow_helpers import (
    T0,
    make_book,
    only_session,
    rec,
)

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths

SID = "session:" + "ab" * 8 + "-" + "cd" * 8
SID2 = "session:" + "12" * 8 + "-" + "34" * 8
DAY = "2026-10-20"


def _put(
    paths: Paths,
    entry_id: str,
    day: str = DAY,
    amount: int = 28,
    kind: str = CREDIT,
    **detail: str,
) -> None:
    row = Entry(entry_id, kind, day, amount, {"ended_at": "1760000000", **detail})
    _ledger.append(paths.ledger, paths.key_file, row)


def _rows(paths: Paths) -> list[Entry]:
    return _ledger.load(paths.ledger, paths.key_file).entries


def test_session_credit_gets_one_top_up_on_the_same_day(bg_paths: Paths) -> None:
    _put(bg_paths, SID, isbn="978", title="War", end_page="29", bonus="1")
    (added,) = _inclusive.backfill(bg_paths)
    assert (added.entry_id, added.kind, added.day, added.amount) == (
        "inclusive:" + SID,
        CREDIT,
        DAY,
        1,
    )
    assert added.detail["topup_of"] == SID
    assert added.detail["ended_at"] == "1760000000"
    assert added.detail["isbn"] == "978"
    assert "bonus" not in added.detail
    assert "end_page" not in added.detail
    assert [e.entry_id for e in _rows(bg_paths)] == [SID, "inclusive:" + SID]


def test_the_day_counts_one_more_page(bg_paths: Paths) -> None:
    _put(bg_paths, SID)
    _put(bg_paths, SID2, day="2026-10-21", amount=10)
    _inclusive.backfill(bg_paths)
    per_day = credits_by_day(_ledger.load(bg_paths.ledger, bg_paths.key_file))
    assert per_day == {DAY: 29, "2026-10-21": 11}


def test_rewritten_summary_credit_is_topped_up_too(bg_paths: Paths) -> None:
    _put(bg_paths, SID + "#2")
    (added,) = _inclusive.backfill(bg_paths)
    assert added.entry_id == "inclusive:" + SID + "#2"


def test_second_run_adds_nothing(bg_paths: Paths) -> None:
    _put(bg_paths, SID)
    assert len(_inclusive.backfill(bg_paths)) == 1
    assert _inclusive.backfill(bg_paths) == []
    assert len(_rows(bg_paths)) == 2


def test_skips_everything_that_is_not_an_old_paper_credit(bg_paths: Paths) -> None:
    _put(bg_paths, "session:ebook-k1")
    _put(bg_paths, "bonus:" + SID, amount=0, bonus="1")
    _put(bg_paths, "bonus:auto:" + DAY, amount=0, bonus="1")
    _put(bg_paths, SID, kind=REJECT, amount=0)
    _put(bg_paths, SID2, counting="inclusive")
    _put(bg_paths, "credit:" + DAY)
    assert _inclusive.backfill(bg_paths) == []
    assert len(_rows(bg_paths)) == 6


def test_dry_run_lists_and_writes_nothing(
    bg_paths: Paths, capsys: pytest.CaptureFixture[str]
) -> None:
    _put(bg_paths, SID)
    _put(bg_paths, SID2, day="2026-10-21")
    before = bg_paths.ledger.read_bytes()
    assert _cli.main(["backfill-inclusive", "--dry-run"]) == 0
    out = capsys.readouterr().out
    assert f"{DAY} +1" in out
    assert "2026-10-21 +1" in out
    assert "total +2" in out
    assert bg_paths.ledger.read_bytes() == before


def test_command_writes_then_is_a_no_op(
    bg_paths: Paths, capsys: pytest.CaptureFixture[str]
) -> None:
    _put(bg_paths, SID)
    assert _cli.main(["backfill-inclusive"]) == 0
    assert "total +1" in capsys.readouterr().out
    assert len(_rows(bg_paths)) == 2
    assert _cli.main(["backfill-inclusive"]) == 0
    assert "nothing to add" in capsys.readouterr().out
    assert len(_rows(bg_paths)) == 2


def test_never_creates_a_bonus_row(bg_paths: Paths) -> None:
    _put(bg_paths, SID, bonus="0")
    _inclusive.backfill(bg_paths)
    assert not [e for e in _rows(bg_paths) if e.detail.get("bonus") == "1"]


def test_new_session_credit_is_marked_and_never_topped_up(bg_paths: Paths) -> None:
    session = only_session([rec("s", 1, T0), rec("e", 29, T0 + timedelta(minutes=40))])
    entry = _quiz.record_verdict(
        bg_paths, make_book(), session, Verdict(True, "f"), "s"
    )
    assert entry is not None
    assert (entry.amount, entry.detail["pages"]) == (29, "29")
    assert entry.detail["counting"] == "inclusive"
    assert _inclusive.backfill(bg_paths) == []


def test_new_reject_row_is_marked_too(bg_paths: Paths) -> None:
    session = only_session([rec("s", 1, T0), rec("e", 9, T0 + timedelta(minutes=40))])
    entry = _quiz.record_verdict(
        bg_paths, make_book(), session, Verdict(False, "f"), "s"
    )
    assert entry is not None
    assert entry.detail["counting"] == "inclusive"
