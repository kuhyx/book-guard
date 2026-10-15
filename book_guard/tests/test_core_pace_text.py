# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``book-guard ask`` as text (_pace_text) and the ``ask`` command."""

from __future__ import annotations

from datetime import date
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

from book_guard import _cli
from book_guard._ask import Ask
from book_guard._ledger import CREDIT, Entry, Ledger
from book_guard._pace import Pace
from book_guard._pace_text import OLD_RULE, detail, row
from book_guard._pace_view import (
    FUTURE,
    PAST,
    TODAY,
    DayView,
)
from book_guard.tests._flow_helpers import add_credit

if TYPE_CHECKING:
    from book_guard._paths import Paths

Out = pytest.CaptureFixture[str]
TODAY_D = date(2026, 10, 15)  # a Thursday
FIXTURE = Path(__file__).resolve().parents[2] / "app/test/fixtures/pace_goldens.json"


def _ledger(pages: dict[date, int]) -> Ledger:
    return Ledger([Entry(f"c{d}", CREDIT, d.isoformat(), n) for d, n in pages.items()])


def _never(_day: date) -> bool:
    return False


# -- text -----------------------------------------------------------------------


def _view(
    day: date = TODAY_D,
    kind: str = TODAY,
    *,
    credited: int = 10,
    assumed: int = 10,
    free: bool = False,
    simulated: int = 0,
    pace: Pace | None = None,
) -> DayView:
    pace = pace or Pace(
        month=date(2026, 10, 1),
        target=1000,
        carried_debt=0,
        pages=200,
        required=200,
        finished_books=0,
        ask=Ask(required=17),
    )
    return DayView(day, kind, pace, credited, assumed, free, simulated)


def test_rows() -> None:
    assert row(_view(date(2026, 9, 30), PAST)).endswith("no quota yet, read 10")
    assert row(_view(free=True)).endswith("free day, read 10")
    assert row(_view(date(2026, 10, 5), PAST)).endswith(
        "old rule (15+15 / 10+10), read 10"
    )
    assert row(_view(credited=20, assumed=20)).endswith("needs  17  read  20  met")
    assert row(_view(credited=3, assumed=17)).endswith(
        "needs  17  read   3 (projection assumes 17)"
    )
    assert row(_view(kind=FUTURE, credited=0, assumed=17)).endswith(
        "needs  17 (assumed 17 read)"
    )
    assert row(_view(simulated=-5, assumed=12)).endswith("(simulated: 12 read, -5)")


def test_details() -> None:
    assert detail(_view(date(2026, 9, 30), PAST))[1].startswith("  no page quota")
    assert detail(_view(date(2026, 10, 5), PAST))[1] == (
        f"  {OLD_RULE}; credited that day: 10 pages"
    )
    free = detail(_view(free=True))
    assert free[0].endswith("(today, live)")
    assert free[1] == "  free day: asks nothing"
    assert free[2].endswith("read 200 (on pace)")
    future = detail(_view(kind=FUTURE, assumed=17))
    assert future[1] == "  requirement: 17 pages (assumed 17 read)"
    owed = Pace(
        month=date(2026, 10, 1),
        target=1000,
        carried_debt=4,
        pages=100,
        required=300,
        finished_books=0,
        carried_credit=2,
        ask=Ask(required=60, debt_per_day=20, debt_days=4, debt_unplaced=10),
    )
    lines = detail(_view(pace=owed))
    assert lines[1] == "  requirement: 60 pages; credited 10"
    assert lines[2].endswith("read 100 (200 behind)")
    assert lines[3] == "  carried from earlier months: debt 4, credit 2"
    assert lines[4] == (
        "  debt: up to 20/day over 4 weekend days; 10 carried into next month"
    )


# -- book-guard ask --------------------------------------------------------------


def test_cli_ask(
    bg_paths: Paths,
    monkeypatch: pytest.MonkeyPatch,
    capsys: Out,
    caplog: pytest.LogCaptureFixture,
) -> None:
    add_credit(bg_paths, TODAY_D.isoformat(), 22)

    class _Now:
        @staticmethod
        def now() -> _Now:
            return _Now()

        def astimezone(self) -> _Now:
            return self

        @staticmethod
        def date() -> date:
            return TODAY_D

    monkeypatch.setattr("book_guard._ask_cli.datetime", _Now)
    assert _cli.main(["ask"]) == 0
    out = capsys.readouterr().out
    assert out.startswith("Thu 2026-10-15 (today, live)\n")
    assert "credited 22" in out
    assert _cli.main(["ask", "--week"]) == 0
    assert len(capsys.readouterr().out.splitlines()) == 7
    assert _cli.main(["ask", "--month", "--simulate=-20@2026-10-16"]) == 0
    month = capsys.readouterr().out.splitlines()
    assert month[0] == "Simulation: -20 pages on 2026-10-16"
    assert len(month) == 32
    assert _cli.main(["ask", "--date", "2026-10-20", "--simulate", "+5"]) == 0
    assert "(future, projected" in capsys.readouterr().out
    assert _cli.main(["ask", "--simulate", "5@2026-10-01"]) == 2
    assert "--simulate: a simulation starts today or later" in caplog.text
