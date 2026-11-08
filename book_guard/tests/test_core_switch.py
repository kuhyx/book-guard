# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Switching back to a book already registered: ``_books.switch``."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

import pytest

from book_guard import _books, _ledger
from book_guard._app_handlers import HANDLERS
from book_guard._books import Chapter
from book_guard._cli import main
from book_guard._grading import switch_book
from book_guard._openlibrary import BookInfo

if TYPE_CHECKING:
    from book_guard._paths import Paths

ZBRODNIA = "9788382220773"
STOIK = "9788311187948"


def _two_books(paths: Paths) -> None:
    _books.register(
        paths,
        BookInfo("Zbrodnia i kara", "Dostojewski", 700, ZBRODNIA),
        pages=611,
        chapters=(Chapter(1, "I"), Chapter(300, "II")),
    )
    _books.register(paths, BookInfo("Stoik", "Piercy", 172, STOIK))


def _ledger_of(paths: Paths) -> _ledger.Ledger:
    return _ledger.load(paths.ledger, paths.key_file)


def test_switch_keeps_pages_and_chapters(bg_paths: Paths) -> None:
    _two_books(bg_paths)
    book = _books.switch(bg_paths, ZBRODNIA)
    assert (book.isbn, book.pages) == (ZBRODNIA, 611)
    assert book.chapters == (Chapter(1, "I"), Chapter(300, "II"))
    assert _books.current(_ledger_of(bg_paths)) == book


def test_switch_from_the_tap_time(bg_paths: Paths) -> None:
    _two_books(bg_paths)
    stoik = _books.current(_ledger_of(bg_paths))
    assert stoik is not None
    # Between the newest row and now: a tap the outbox delivered late.
    tap = stoik.registered_at + timedelta(microseconds=50)
    book = _books.switch(bg_paths, ZBRODNIA, at=tap)
    assert book.registered_at == tap
    ledger = _ledger_of(bg_paths)
    assert _books.book_at(ledger, tap + timedelta(seconds=1)) == book
    assert _books.book_at(ledger, tap - timedelta(microseconds=25)) == stoik


def test_switch_never_reaches_before_the_newest_book(bg_paths: Paths) -> None:
    _two_books(bg_paths)
    newest = _books.current(_ledger_of(bg_paths))
    assert newest is not None
    book = _books.switch(
        bg_paths, ZBRODNIA, at=newest.registered_at - timedelta(days=1)
    )
    assert book.registered_at > newest.registered_at


def test_switch_never_in_the_future(bg_paths: Paths) -> None:
    _two_books(bg_paths)
    book = _books.switch(
        bg_paths, ZBRODNIA, at=datetime.now(tz=UTC) + timedelta(days=1)
    )
    assert book.registered_at <= datetime.now(tz=UTC)


def test_switch_to_the_current_book_writes_nothing(bg_paths: Paths) -> None:
    _two_books(bg_paths)
    before = bg_paths.ledger.read_bytes()
    assert _books.switch(bg_paths, STOIK).isbn == STOIK
    assert bg_paths.ledger.read_bytes() == before


def test_switch_to_an_unknown_book_is_refused(bg_paths: Paths) -> None:
    _two_books(bg_paths)
    with pytest.raises(LookupError, match="not registered"):
        _books.switch(bg_paths, "9780000000000")


def test_switch_times_are_the_switch_rows(bg_paths: Paths) -> None:
    _two_books(bg_paths)
    assert _books.switch_times(_ledger_of(bg_paths)) == []
    book = _books.switch(bg_paths, ZBRODNIA)
    assert _books.switch_times(_ledger_of(bg_paths)) == [book.registered_at]


def test_switch_book_line(bg_paths: Paths) -> None:
    _two_books(bg_paths)
    assert switch_book(bg_paths, ZBRODNIA) == (
        True,
        "Now reading: Zbrodnia i kara -- Dostojewski, last page 611",
    )
    ok, message = switch_book(bg_paths, "9780000000000")
    assert not ok
    assert "not registered" in message


def test_switch_request(bg_paths: Paths) -> None:
    _two_books(bg_paths)
    tap = datetime.now(tz=UTC).astimezone()
    answer = HANDLERS["switch_book"](
        bg_paths, {"isbn": ZBRODNIA, "at": tap.isoformat()}
    )
    assert answer.ok
    assert answer.message.startswith("Now reading: Zbrodnia i kara")
    now_reading = _books.current(_ledger_of(bg_paths))
    assert now_reading is not None
    assert now_reading.isbn == ZBRODNIA


@pytest.mark.parametrize(
    ("body", "why"),
    [
        ({"isbn": "x"}, "ISBN"),
        ({"isbn": ZBRODNIA, "at": "yesterday"}, "time"),
        ({"isbn": ZBRODNIA, "at": "2026-11-08T08:00:00"}, "time"),
    ],
)
def test_switch_request_rejects(
    bg_paths: Paths, body: dict[str, str], why: str
) -> None:
    _two_books(bg_paths)
    answer = HANDLERS["switch_book"](bg_paths, body)
    assert not answer.ok
    assert why in answer.message


def test_switch_request_without_a_time_is_now(bg_paths: Paths) -> None:
    _two_books(bg_paths)
    assert HANDLERS["switch_book"](bg_paths, {"isbn": ZBRODNIA}).ok


def test_switch_cli(bg_paths: Paths, capsys: pytest.CaptureFixture[str]) -> None:
    _two_books(bg_paths)
    assert main(["switch", ZBRODNIA]) == 0
    assert "Now reading: Zbrodnia" in capsys.readouterr().out
    assert main(["switch", "9780000000000"]) == 1
