# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What the lock, the status CLI and the toast show: icons and numbers.

The human-facing surfaces carry no sentences (kuhy, 2026-11-08). This module
turns a snapshot into a small view model -- gauges, chores, session rows --
and renders it as glyph lines; the Tk window draws the same model with
``_icons``. The wordy ``_render`` text still feeds NEXT.txt and state.json
(read by the phone app), which are not these surfaces.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Final

from book_guard._constants import DAILY_PASS_PAGES, ESCAPES_PER_MONTH
from book_guard._sessions import NEEDS_CHECK, NEEDS_QUIZ, TOO_FAST
from book_guard._state import CREDITED
from book_guard._state import OVERLAP as OVERLAP_STATUS

if TYPE_CHECKING:
    from book_guard._books import Book
    from book_guard._sessions import Session
    from book_guard._state import SessionView, Snapshot

BOOK: Final = "book"
CAMERA: Final = "camera"
PENCIL: Final = "pencil"
LOCK: Final = "lock"
UNLOCK: Final = "unlock"
OK: Final = "ok"
NO: Final = "no"
FAST: Final = "fast"
OVERLAP: Final = "overlap"
SICK: Final = "sick"
RETRY: Final = "retry"
WARN: Final = "warn"
MONTH: Final = "month"
DAY: Final = "day"
DEBT: Final = "debt"
ESCAPE: Final = "escape"

GLYPH: Final = {
    BOOK: "📖",
    CAMERA: "📷",
    PENCIL: "✎",
    LOCK: "🔒",
    UNLOCK: "🔓",
    OK: "✓",
    NO: "✗",
    FAST: "≫",
    OVERLAP: "⧉",
    SICK: "✚",
    RETRY: "↻",
    WARN: "⚠",
    MONTH: "▦",
    DAY: "☀",
    DEBT: "▼",
    ESCAPE: "⎋",
}
"""Text-mode glyphs (terminal, toast) for every drawn icon."""

_MARKS: Final = {
    NEEDS_CHECK: CAMERA,
    NEEDS_QUIZ: PENCIL,
    TOO_FAST: FAST,
    CREDITED: OK,
    OVERLAP_STATUS: OVERLAP,
}
_BAR: Final = 12


@dataclass(frozen=True)
class Gauge:
    """A count against a total; ``mark`` is a line on the bar (the pace)."""

    icon: str
    value: int
    total: int
    mark: int | None = None
    done: bool = False


@dataclass(frozen=True)
class Chore:
    """Something to do: an icon, a number, and an optional second icon."""

    icon: str
    number: str
    badge: str = ""


@dataclass(frozen=True)
class Entry:
    """One session: its pages, size in pages and minutes, when, and a mark."""

    pages: str
    size: str
    when: str
    mark: str
    number: str = ""


@dataclass(frozen=True)
class View:
    """The whole snapshot as icons and numbers."""

    locked: bool
    book: str
    last_page: int
    month: str
    gauges: tuple[Gauge, ...]
    chores: tuple[Chore, ...]
    entries: tuple[Entry, ...]
    escapes_left: int
    escapes_total: int


def _span(s: Session) -> str:
    """``40-65``; ``≈40-65`` when read in the app (an estimate)."""
    return f"{'≈' if s.estimated else ''}{s.start.page}-{s.end.page}"


def _gauges(snap: Snapshot) -> tuple[Gauge, ...]:
    p = snap.pace
    gauges = [Gauge(MONTH, p.pages, p.target, mark=p.required, done=not p.behind)]
    if snap.sick_today:
        gauges.append(Gauge(SICK, p.pages_today, 0, done=bool(p.ask.bonus)))
    elif p.ask.required:
        gauges.append(Gauge(DAY, p.pages_today, p.ask.required, done=bool(p.ask.bonus)))
    if not p.ask.daily:
        gauges.append(
            Gauge(UNLOCK, p.pages_today, DAILY_PASS_PAGES, done=p.passed_today)
        )
    if p.behind:
        gauges.append(Gauge(DEBT, p.behind, p.behind))
    return tuple(gauges)


def _chores(snap: Snapshot) -> tuple[Chore, ...]:
    chores = [
        Chore(CAMERA, str(v.session.check_page)) for v in snap.with_status(NEEDS_CHECK)
    ]
    chores += [
        Chore(PENCIL, _span(v.session), RETRY if v.verdicts else "")
        for v in snap.with_status(NEEDS_QUIZ)
    ]
    if snap.open_start is not None:
        chores.append(Chore(BOOK, f"{snap.open_start.page}→", CAMERA))
    if snap.book is None:
        chores.append(Chore(BOOK, "?"))
    return tuple(chores)


def _entry(view: SessionView) -> Entry:
    s = view.session
    mark = _MARKS.get(view.status, NO)
    number = str(s.check_page) if view.status == NEEDS_CHECK else ""
    when = s.started_at.astimezone().strftime("%d.%m %H:%M")
    return Entry(_span(s), f"▤{s.pages} ◷{s.minutes}", when, mark, number)


def build(snap: Snapshot, *, recent: int = 4) -> View:
    """The snapshot as a view model."""
    book = snap.book
    return View(
        locked=snap.locked,
        book=book.label if book else "",
        last_page=book.pages or 0 if book else 0,
        month=f"{snap.pace.month:%Y-%m}",
        gauges=_gauges(snap),
        chores=_chores(snap),
        entries=tuple(_entry(v) for v in snap.sessions[-recent:]) if recent else (),
        escapes_left=snap.escapes_left,
        escapes_total=ESCAPES_PER_MONTH,
    )


def meter_text(value: int, total: int, mark: int | None = None) -> str:
    """``█████░░░░░░░`` with a ``│`` at the pace line when there is one."""
    filled = min(_BAR, round(_BAR * value / total)) if total else 0
    cells = ["█"] * filled + ["░"] * (_BAR - filled)
    if mark is not None and total:
        cells[min(_BAR - 1, round(_BAR * mark / total))] = "│"
    return "".join(cells)


def _chore_text(chore: Chore) -> str:
    parts = [GLYPH[chore.icon], chore.number]
    if chore.badge:
        parts.append(GLYPH[chore.badge])
    return " ".join(p for p in parts if p)


def text_lines(snap: Snapshot, *, recent: int = 6) -> list[str]:
    """The terminal rendering. Line 0 carries the book title (user content)."""
    view = build(snap, recent=recent)
    state = GLYPH[LOCK if view.locked else UNLOCK]
    last = f" ▤{view.last_page}" if view.last_page else ""
    lines = [f"{state} {GLYPH[BOOK]} {view.book or '?'}{last}"]
    for g in view.gauges:
        done = f" {GLYPH[OK]}" if g.done else ""
        mark = f" │{g.mark}" if g.mark is not None else ""
        head = f"{GLYPH[g.icon]} {view.month}" if g.icon == MONTH else GLYPH[g.icon]
        meter = meter_text(g.value, g.total, g.mark)
        lines.append(f"{head} {meter} {g.value}/{g.total}{mark}{done}")
    left = "●" * view.escapes_left + "○" * (view.escapes_total - view.escapes_left)
    lines.append(f"{GLYPH[ESCAPE]} {left}")
    lines += [_chore_text(c) for c in view.chores]
    lines += [
        f"  {e.pages} {e.size} {e.when} {GLYPH[e.mark]} {e.number}".rstrip()
        for e in view.entries
    ]
    return lines


def toast_body(snap: Snapshot) -> str:
    """The desktop notification body: one glyph line per chore, or empty."""
    return "\n".join(_chore_text(c) for c in _chores(snap))


_TOAST_ICONS: Final = {
    CAMERA: "camera-photo",
    PENCIL: "document-edit",
    BOOK: "x-office-document",
}
"""Freedesktop icon names, the toast's second channel next to its glyphs."""


def toast_icon(snap: Snapshot) -> str:
    """The icon of the most urgent chore (the first one listed)."""
    chores = _chores(snap)
    return _TOAST_ICONS[chores[0].icon] if chores else ""


def session_text(view: SessionView) -> str:
    """One session as a glyph line: ``18-20 ▤3 ◷20 15.10 09:28 ✎``."""
    e = _entry(view)
    return f"{e.pages} {e.size} {e.when} {GLYPH[e.mark]} {e.number}".rstrip()


def book_line(book: Book) -> str:
    """``✓ 📖 <title> ▤<last page>``: the book as registered (user content)."""
    pages = f" ▤{book.pages}" if book.pages else ""
    return f"{GLYPH[OK]} {GLYPH[BOOK]} {book.label}{pages}"
