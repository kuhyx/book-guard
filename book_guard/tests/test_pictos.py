# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The text-free view model: what the lock, the status CLI and the toast show.

The asserts are on structure (icons, numbers, flags), never on sentences:
the surfaces carry no words, so there is no sentence to pin.
"""

from __future__ import annotations

from dataclasses import replace
from datetime import date
import re
from typing import TYPE_CHECKING, Any, cast

from book_guard import _icons
from book_guard import _pictos as p
from book_guard._ask import Ask
from book_guard._constants import DAILY_PASS_PAGES, ESCAPES_PER_MONTH
from book_guard._sessions import NEEDS_CHECK, NEEDS_QUIZ
from book_guard._state import SessionView, snapshot
from book_guard.tests._flow_helpers import (
    LOCKED_DAY,
    T0,
    make_book,
    make_snap,
    quiz_pair,
    rec,
    seed_photos,
)
from book_guard.tests.test_flow_render import CHECK

_VERDICTS: Any = (object(),)
if TYPE_CHECKING:
    import tkinter as tk

    from book_guard._paths import Paths

LETTERS = re.compile(r"[A-Za-z]{2,}")


def test_every_icon_has_a_glyph_and_a_drawing() -> None:

    assert set(p.GLYPH) == set(_icons.SHAPES)


def test_view_of_a_quiet_snapshot() -> None:
    view = p.build(make_snap(book=make_book()))
    assert view.escapes_total == ESCAPES_PER_MONTH
    assert view.gauges[0].icon == p.MONTH
    assert view.chores == ()
    assert view.entries == ()


def test_chores_carry_icons_and_numbers_only() -> None:
    session_check = SessionView(CHECK, None, NEEDS_CHECK)
    session_quiz = SessionView(CHECK, None, NEEDS_QUIZ)
    snap = replace(make_snap(book=make_book()), sessions=[session_check, session_quiz])
    chores = p.build(snap).chores
    assert [c.icon for c in chores] == [p.CAMERA, p.PENCIL]
    assert chores[0].number == str(CHECK.check_page)
    for c in chores:
        assert not LETTERS.search(c.number)


def test_failed_summary_asks_again_with_a_retry_badge() -> None:
    again = SessionView(CHECK, None, NEEDS_QUIZ, verdicts=_VERDICTS)
    chore = p.build(replace(make_snap(), sessions=[again])).chores[0]
    assert (chore.icon, chore.badge) == (p.PENCIL, p.RETRY)


def test_no_book_is_a_book_with_a_question_mark() -> None:
    chore = p.build(make_snap()).chores[-1]
    assert (chore.icon, chore.number) == (p.BOOK, "?")


def test_gauges_follow_the_pace() -> None:
    snap = make_snap(book=make_book())
    view = p.build(snap)
    month = view.gauges[0]
    assert (month.value, month.total, month.mark) == (
        snap.pace.pages,
        snap.pace.target,
        snap.pace.required,
    )
    today = [g for g in view.gauges if g.icon == p.UNLOCK]
    if today:
        assert today[0].total == DAILY_PASS_PAGES


def test_text_lines_have_no_words() -> None:
    snap = make_snap(book=make_book(author=""))
    lines = p.text_lines(snap, recent=3)
    body = "\n".join(lines[1:])  # line 0 holds the book title: user content
    assert not LETTERS.search(body)
    assert "War" in lines[0]


def test_toast_is_glyphs_and_numbers() -> None:
    seed = replace(make_snap(), sessions=[SessionView(CHECK, None, NEEDS_CHECK)])
    body = p.toast_body(seed)
    assert p.GLYPH[p.CAMERA] in body
    assert not LETTERS.search(body)
    assert p.toast_body(make_snap(book=make_book())) == ""


def test_snapshot_from_the_ledger(bg_paths: Paths) -> None:

    seed_photos(bg_paths, *quiz_pair())
    view = p.build(snapshot(bg_paths, today=LOCKED_DAY))
    assert view.locked
    assert view.chores[0].icon == p.PENCIL


def _with_ask(**ask: Any) -> Any:
    snap = make_snap(book=make_book())
    return replace(snap, pace=replace(snap.pace, ask=Ask(**ask)))


def test_daily_ask_gauge_and_sick_day() -> None:
    daily = p.build(_with_ask(required=15, bonus=True, daily=True))
    assert [g.icon for g in daily.gauges] == [p.MONTH, p.DAY, p.DEBT]
    assert daily.gauges[1].done
    sick = replace(_with_ask(), sick_days=frozenset({date(2026, 10, 5)}))
    assert p.build(sick).gauges[1].icon == p.SICK


def test_reading_in_progress_points_at_the_camera() -> None:
    start = rec("open", 50, T0)
    snap = replace(make_snap(book=make_book()), open_start=start)
    assert p.build(snap).chores == (p.Chore(p.BOOK, "50→", p.CAMERA),)
    assert p.text_lines(snap)[-1] == f"{p.GLYPH[p.BOOK]} 50→ {p.GLYPH[p.CAMERA]}"
    assert p.toast_icon(snap) == "x-office-document"
    assert p.toast_icon(make_snap(book=make_book())) == ""


def test_bar_without_a_total_is_empty() -> None:
    assert p.meter_text(3, 0, 1) == "░" * 12
    assert p.meter_text(99, 10) == "█" * 12


def test_session_text_names_its_mark() -> None:
    line = p.session_text(SessionView(CHECK, None, NEEDS_CHECK))
    assert line.endswith(f"{p.GLYPH[p.CAMERA]} {CHECK.check_page}")


def test_book_line_is_a_tick_a_book_and_its_pages() -> None:
    line = p.book_line(make_book(pages=412))
    assert line == f"{p.GLYPH[p.OK]} {p.GLYPH[p.BOOK]} War -- Tol ▤412"
    assert p.book_line(make_book(pages=None)).endswith("War -- Tol")


def test_draw_paints_every_shape_kind() -> None:
    class Canvas:
        def __init__(self) -> None:
            self.calls: list[str] = []

        def __getattr__(self, name: str) -> Any:
            return lambda *_a, **_k: self.calls.append(name)

    canvas = Canvas()
    for name in _icons.SHAPES:
        _icons.draw(cast("tk.Canvas", canvas), name, size=48, color="#fff")
    assert set(canvas.calls) == {
        "create_rectangle",
        "create_oval",
        "create_polygon",
        "create_line",
    }
