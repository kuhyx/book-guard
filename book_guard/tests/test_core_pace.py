# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_pace (year balance, free days, finished books) and _books (registrations)."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from typing import TYPE_CHECKING

import pytest

from book_guard import _books, _ledger, _pace
from book_guard._constants import (
    GATE_START_DATE,
    MONTHLY_PAGES,
    OFFDAY_PAGES,
    WORKDAY_PAGES,
)
from book_guard._ledger import BOOK, CREDIT, ESCAPE, Entry, Ledger
from book_guard._openlibrary import BookInfo

if TYPE_CHECKING:
    from book_guard._paths import Paths


# October 2026 (from the 2nd: 12 Tue-Thu and 18 Fri-Mon days) is the last
# month whose base is its quota sum; every later month's is MONTHLY_PAGES.
OCTOBER = 12 * WORKDAY_PAGES + 18 * OFFDAY_PAGES


def _never(_day: date) -> bool:
    return False


def _book(isbn: str, pages: str, created: str, *, title: str = "T") -> Entry:
    return Entry(
        entry_id=f"book:{isbn}:{created}",
        kind=BOOK,
        day=created[:10],
        detail={"isbn": isbn, "title": title, "author": "", "pages": pages},
        created_at=created,
    )


def _credit(day: str, amount: int, *, isbn: str = "", end_page: str = "") -> Entry:
    return Entry(
        entry_id=f"credit:{day}:{amount}:{end_page}",
        kind=CREDIT,
        day=day,
        amount=amount,
        detail={"isbn": isbn, "end_page": end_page},
    )


def test_month_helpers() -> None:
    assert _pace.month_start(date(2026, 12, 31)) == date(2026, 12, 1)
    assert _pace._next_month(date(2026, 12, 1)) == date(2027, 1, 1)
    assert len(_pace._days(date(2027, 2, 1))) == 28


def test_before_gate_start_nothing_is_owed() -> None:
    ledger = Ledger([_credit("2026-09-10", 50)])
    pace = _pace.compute_pace(ledger, date(2026, 9, 20), _never)
    assert (pace.month, pace.target, pace.carried_debt) == (date(2026, 9, 1), 0, 0)
    assert pace.pages == 50
    assert pace.required == 0
    assert pace.behind == 0


def test_first_day_of_gate_requires_nothing() -> None:
    pace = _pace.compute_pace(Ledger(), GATE_START_DATE, _never)
    assert pace.required == 0
    # Oct 1 predates the quotas: the line on Oct 3 is Friday's 40 alone.
    assert _pace.compute_pace(Ledger(), date(2026, 10, 3), _never).required == 40


def test_required_is_prorated_over_elapsed_days() -> None:
    ledger = Ledger([_credit("2026-10-03", 40), _credit("2026-09-30", 500)])
    pace = _pace.compute_pace(ledger, date(2026, 10, 11), _never)
    assert pace.target == OCTOBER
    assert pace.pages == 40
    # Oct 2-10: Fri Sat Sun Mon (4x40) Tue Wed Thu (3x20) Fri Sat (2x40)
    assert pace.required == 4 * 40 + 3 * 20 + 2 * 40
    assert pace.behind == pace.required - 40


def test_debt_carries_across_months() -> None:
    ledger = Ledger([_credit("2026-10-05", 100), _credit("2026-11-02", 700)])
    # 860 short, split over November and December.
    november = _pace.compute_pace(ledger, date(2026, 11, 1), _never)
    assert november.carried_debt == 430
    assert november.target == MONTHLY_PAGES + 430
    # December is the year's last month: all 860 + 300 short in November.
    december = _pace.compute_pace(ledger, date(2026, 12, 1), _never)
    assert december.carried_debt == 860 + MONTHLY_PAGES - 700
    # January takes December's whole balance.
    january = _pace.compute_pace(Ledger(), date(2027, 1, 15), _never)
    assert january.carried_debt == OCTOBER + 2 * MONTHLY_PAGES


def test_surplus_carries_across_months() -> None:
    # 2000 pages by Oct 5 read October's 960 and 1040 ahead.
    ledger = Ledger([_credit("2026-10-05", 2000)])
    november = _pace.compute_pace(ledger, date(2026, 11, 1), _never)
    assert (november.carried_credit, november.target) == (520, MONTHLY_PAGES - 520)
    december = _pace.compute_pace(ledger, date(2026, 12, 1), _never)
    assert december.carried_debt == 0
    assert december.carried_credit == 2000 - OCTOBER - MONTHLY_PAGES
    assert december.target == MONTHLY_PAGES - december.carried_credit


def test_finished_book_clears_no_debt() -> None:
    ledger = Ledger(
        [
            _book("111", "250", "2026-10-01T08:00:00+00:00"),
            _book("222", "", "2026-10-01T09:00:00+00:00"),
            _credit("2026-10-10", 20, isbn="111", end_page="250"),
            _credit("2026-10-11", 5, isbn="111", end_page="249"),
            _credit("2026-10-12", 5, isbn="111", end_page="n/a"),
            _credit("2026-10-13", 5, isbn="222", end_page="999"),
            _credit("2026-10-14", 5, isbn="333", end_page="999"),
            Entry(entry_id="esc", kind=ESCAPE, day="2026-10-15"),
        ]
    )
    october = _pace.compute_pace(ledger, date(2026, 10, 20), _never)
    assert october.finished_books == 1
    assert october.pages == 40
    # Only pages count: finishing a book forgives none of the shortfall.
    november = _pace.compute_pace(ledger, date(2026, 11, 3), _never)
    assert november.carried_debt == (OCTOBER - 40) // 2


def test_free_days_move_the_line() -> None:
    free = {date(2026, 10, d) for d in range(1, 11)}
    pace = _pace.compute_pace(Ledger(), date(2026, 10, 11), free.__contains__)
    assert pace.required == 0
    later = _pace.compute_pace(Ledger(), date(2026, 10, 16), free.__contains__)
    # Oct 11-15 counted: Sun Mon (2x40) Tue Wed Thu (3x20)
    assert later.required == 2 * 40 + 3 * 20
    assert later.target == OCTOBER - (4 * 40 + 3 * 20 + 2 * 40)


def test_all_days_free() -> None:
    pace = _pace.compute_pace(Ledger(), date(2026, 10, 20), lambda _d: True)
    assert pace.required == 0


def test_debt_survives_a_fully_free_month() -> None:
    def november_free(day: date) -> bool:
        return day.month == 11

    november = _pace.compute_pace(Ledger(), date(2026, 11, 20), november_free)
    owed = MONTHLY_PAGES + OCTOBER // 2
    assert (november.target, november.required) == (owed, 0)
    december = _pace.compute_pace(Ledger(), date(2026, 12, 1), november_free)
    assert december.carried_debt == OCTOBER + MONTHLY_PAGES


def test_surplus_lightens_workdays_not_tomorrow() -> None:
    ledger = Ledger([_credit("2026-10-02", 44)])
    saturday = _pace.compute_pace(ledger, date(2026, 10, 3), _never)
    assert (saturday.required, saturday.behind) == (44, 0)
    # Saturday's 40 is still owed in full: the 4 extra went to the workdays.
    sunday = _pace.compute_pace(ledger, date(2026, 10, 4), _never)
    assert sunday.required == 44 + 40
    # Tuesday lost 4/12 of a page: 44 + 3x40 + 19.67 rounds up to 184.
    wednesday = _pace.compute_pace(ledger, date(2026, 10, 7), _never)
    assert wednesday.required == 184
    assert wednesday.target == OCTOBER


def test_surplus_past_the_workdays_lightens_fri_to_mon() -> None:
    # 260 extra: the 12 remaining workdays absorb 240, then 20 is split over
    # the 17 remaining Fri-Mon days.
    ledger = Ledger([_credit("2026-10-02", 300)])
    wednesday = _pace.compute_pace(ledger, date(2026, 10, 7), _never)
    assert wednesday.required == 417  # 300 + 3 * (40 - 20/17), Tue at 0
    assert wednesday.target == OCTOBER


def test_book_label_and_lookup() -> None:
    first = _book("111", "300", "2025-01-01T08:00:00+00:00", title="One")
    second = _book("222", "x", "2025-01-05T08:00:00+00:00", title="Two")
    ledger = Ledger([first, second, _credit("2026-10-02", 3)])
    books = _books.all_books(ledger)
    assert [(b.isbn, b.pages) for b in books] == [("111", 300), ("222", None)]
    assert books[0].label == "One"
    moment = datetime(2025, 1, 3, tzinfo=UTC)
    assert _books.book_at(ledger, moment) == books[0]
    assert _books.book_at(ledger, moment + timedelta(days=10)) == books[1]
    assert _books.book_at(ledger, moment - timedelta(days=10)) == books[0]
    assert _books.book_at(Ledger(), moment) is None
    assert _books.current(ledger) == books[1]


def test_label_with_author() -> None:
    book = _books.Book("1", "Solaris", "Lem", 204, datetime.now(tz=UTC))
    assert book.label == "Solaris -- Lem"


def test_register_writes_signed_entry(bg_paths: Paths) -> None:
    book = _books.register(bg_paths, BookInfo("Solaris", "Lem", 204, "978"))
    assert (book.isbn, book.title, book.author, book.pages) == (
        "978",
        "Solaris",
        "Lem",
        204,
    )
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert _books.current(ledger) == book
    override = _books.register(bg_paths, BookInfo("S", "", 204, "978"), pages=190)
    assert override.pages == 190
    unknown = _books.register(bg_paths, BookInfo("S", "", None, "979"))
    assert unknown.pages is None
    entries = _ledger.load(bg_paths.ledger, bg_paths.key_file).of_kind(BOOK)
    assert [e.detail["pages"] for e in entries] == ["204", "190", ""]


def test_register_needs_isbn(bg_paths: Paths) -> None:
    with pytest.raises(ValueError, match="needs an ISBN"):
        _books.register(bg_paths, BookInfo("T", "A", 10, None))
    assert not bg_paths.ledger.exists()
