# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Each credit leaves a signed ``progress`` row: pages done of the day's target.

The row is inert: nothing in the gate reads it, a later release of
``earned_time`` pays the reading bonus in proportion from it.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
import json
from typing import TYPE_CHECKING, cast

import earned_time
import pytest

from book_guard import _bonus, _ledger, _progress, _quiz
from book_guard._ledger import CREDIT, PROGRESS, Entry
from book_guard._pace import compute_pace
from book_guard._quiz import Verdict
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import add_credit, make_book, only_session, rec

if TYPE_CHECKING:
    from book_guard._paths import Paths

TUE = date(2026, 10, 13)
"""Nothing read: Tue asks 18 pages (see test_flow_bonus_day)."""
WED = TUE + timedelta(days=1)
EVENING = datetime(2026, 10, 13, 16, 0, tzinfo=UTC)


class DiskFullError(OSError):
    """The write the progress row needed failed."""


def _read(paths: Paths, pages: int, tag: str, *, day: date = TUE) -> Entry:
    """Credit a session of ``pages`` pages read on ``day`` through the real writer."""
    start = EVENING + timedelta(days=(day - TUE).days, minutes=len(tag) * 90)
    session = only_session(
        [
            rec(f"{tag}-start", 10, start),
            rec(f"{tag}-end", 9 + pages, start + timedelta(minutes=60)),
        ]
    )
    entry = _quiz.record_verdict(paths, make_book(), session, Verdict(True, "f"), "s")
    assert entry is not None
    return entry


def _rows(paths: Paths) -> list[dict[str, object]]:
    raw = json.loads(paths.ledger.read_text(encoding="utf-8"))
    return [r for r in raw["entries"] if r["kind"] == PROGRESS]


def _detail(row: dict[str, object]) -> dict[str, str]:
    return cast("dict[str, str]", row["detail"])


def _ids(paths: Paths) -> list[str]:
    return [str(r["entry_id"]) for r in _rows(paths)]


def test_a_credit_writes_a_progress_row_the_shared_key_verifies(
    bg_paths: Paths,
) -> None:
    credit = _read(bg_paths, 10, "a")
    (row,) = _rows(bg_paths)
    assert row["entry_id"] == "progress:2026-10-13:10:18"
    assert (row["kind"], row["day"], row["amount"]) == (PROGRESS, "2026-10-13", 0)
    assert row["device"] == credit.device
    assert row["created_at"]
    assert row["detail"] == {
        "source": "reading",
        "for_day": "2026-10-13",
        "done": "10",
        "target": "18",
    }
    assert earned_time.verified(row, bg_paths.key_file.read_bytes())
    forged = {**row, "detail": {**_detail(row), "done": "18"}}
    assert not earned_time.verified(forged, bg_paths.key_file.read_bytes())


def test_a_later_credit_the_same_day_writes_the_larger_done(bg_paths: Paths) -> None:
    _read(bg_paths, 10, "a")
    _read(bg_paths, 5, "bb")
    assert _ids(bg_paths) == ["progress:2026-10-13:10:18", "progress:2026-10-13:15:18"]


def test_done_is_capped_at_the_target_and_not_written_twice(bg_paths: Paths) -> None:
    _read(bg_paths, 15, "a")
    _read(bg_paths, 10, "bb")
    _read(bg_paths, 4, "ccc")
    assert _ids(bg_paths) == ["progress:2026-10-13:15:18", "progress:2026-10-13:18:18"]


def test_the_literal_ten_of_thirty_and_five_more(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(_progress, "day_requirement", lambda _l, _d: 30)
    _read(bg_paths, 10, "a")
    _read(bg_paths, 5, "bb")
    assert _ids(bg_paths) == ["progress:2026-10-13:10:30", "progress:2026-10-13:15:30"]


def test_pages_read_later_never_touch_an_earlier_day(bg_paths: Paths) -> None:
    _read(bg_paths, 10, "a")
    before = _rows(bg_paths)
    _read(bg_paths, 40, "bb", day=WED)
    rows = _rows(bg_paths)
    assert rows[: len(before)] == before
    (wed,) = rows[len(before) :]
    detail = _detail(wed)
    # 40 pages read: done is capped at that day's own target.
    assert (wed["day"], detail["for_day"]) == ("2026-10-14", "2026-10-14")
    assert detail["done"] == detail["target"]
    assert int(detail["target"]) >= 1
    assert all(r["day"] != "2026-10-13" for r in rows[len(before) :])


def test_a_day_that_asks_nothing_writes_no_row(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("freedays.is_free_day", lambda day=None, **_k: day == TUE)
    _read(bg_paths, 5, "a")
    assert _rows(bg_paths) == []


def test_a_rejected_session_and_an_empty_day_write_no_row(bg_paths: Paths) -> None:
    session = only_session(
        [rec("r-start", 10, EVENING), rec("r-end", 20, EVENING + timedelta(hours=1))]
    )
    _quiz.record_verdict(bg_paths, make_book(), session, Verdict(False, "f"), "s")
    assert _rows(bg_paths) == []
    assert _progress.record(bg_paths, TUE) is None


def test_before_the_quota_switch_writes_no_row(bg_paths: Paths) -> None:
    add_credit(bg_paths, "2026-10-05", 20)
    assert _progress.record(bg_paths, date(2026, 10, 5)) is None


@pytest.mark.parametrize("broken", ["requirement", "write"])
def test_a_failing_progress_row_keeps_the_credit_and_warns(
    bg_paths: Paths,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
    broken: str,
) -> None:
    def boom(*_a: object) -> int:
        raise DiskFullError

    if broken == "requirement":
        monkeypatch.setattr(_progress, "day_requirement", boom)
    else:
        monkeypatch.setattr(_progress, "append", boom)
    credit = _read(bg_paths, 10, "a")
    loaded = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert [e.entry_id for e in loaded.of_kind(CREDIT)] == [credit.entry_id]
    assert _rows(bg_paths) == []
    assert any(r.levelname == "ERROR" for r in caplog.records)
    assert "progress row" in caplog.text


def _with_junk_progress(paths: Paths, today: date) -> None:
    """Progress rows on October days and on ``today``, some with a page amount."""
    days = {"2026-10-13", "2026-10-30", today.isoformat()}
    for day in sorted(days):
        for amount, (done, target) in enumerate(((1, 1), (999, 5), (0, 0))):
            _ledger.append(
                paths.ledger,
                paths.key_file,
                Entry(
                    f"progress:{day}:{done}:{target}",
                    PROGRESS,
                    day,
                    amount=amount * 7,
                    detail={
                        "source": "reading",
                        "for_day": day,
                        "done": str(done),
                        "target": str(target),
                    },
                ),
            )


@pytest.mark.parametrize(
    ("reads", "today"),
    [
        ([], TUE),
        ([("2026-10-12", 30)], TUE),
        ([("2026-10-13", 10)], TUE),
        ([("2026-10-12", 5), ("2026-10-13", 40)], WED),
        ([("2026-10-13", 2000)], WED),
        ([("2026-10-12", 30), ("2026-10-30", 200)], date(2026, 11, 5)),
    ],
)
def test_no_decision_reads_a_progress_row(
    bg_paths: Paths, reads: list[tuple[str, int]], today: date
) -> None:
    for day, pages in reads:
        add_credit(bg_paths, day, pages)

    def observe() -> tuple[object, ...]:
        ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
        snap = snapshot(
            bg_paths, today=today, is_free=lambda _d: False, sick=frozenset()
        )
        pace = compute_pace(ledger, today, lambda _d: False, sick=frozenset())
        return (
            snap.pace,
            snap.locked,
            snap.reason,
            pace.carried_debt,
            pace.carried_credit,
            _bonus.day_requirement(ledger, today),
            [e.entry_id for e in ledger.of_kind(CREDIT)],
        )

    without = observe()
    _with_junk_progress(bg_paths, today)
    assert observe() == without


def test_deleting_the_ledger_earns_nothing(bg_paths: Paths) -> None:
    _read(bg_paths, 18, "a")
    assert _rows(bg_paths)
    bg_paths.ledger.unlink()
    snap = snapshot(bg_paths, today=TUE, is_free=lambda _d: False, sick=frozenset())
    assert (snap.pace.pages, snap.pace.pages_today, snap.pace.ask.bonus) == (
        0,
        0,
        False,
    )
    assert _progress.record(bg_paths, TUE) is None
