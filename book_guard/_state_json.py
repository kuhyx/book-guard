# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The snapshot as JSON for the app -- written next to NEXT.txt every pass.

Schema version 1. Every field the app shows comes from here; the app never
derives pace or session state itself, so the PC stays the only authority.

``pace.today_required`` is what earns the +1h bonus: the day's requirement
(its quota after surplus moves, plus its weekend debt share), or on a sick
day the requirement it would have had; ``pace.bonus_today`` says a credit
today already has it. ``sick_today`` is a sick day (``sickdays``) that does
not keep ``book``: never locked, and ``pace.today_quota`` (what the day asks)
is 0. A sick day that keeps ``book`` reads as a normal day here.
``pace.debt_per_day`` is the debt asked of each of the ``debt_days_left``
remaining weekend days (Sat/Sun, at most 60 a day with the base quota);
``debt_unplaced`` fits on no day and carries into next month.

``claude_down_since`` is when the current Claude outage began (null when
there is none, or it is over); ``claude_down_until`` (added 2026-10-18) is
when it ends by the CLI's own word ("resets 4:40pm"), or null when the error
named no time. Both go null the instant the flag stops being true: a grade
went through (Claude or the local model), or ``until`` passed -- the app
compares ``until`` with its own clock too, so its note goes on time
without a fresh state.json.

``index_job`` is the last dropped book file's indexing (``_indexjob``):
``{file, stage, done, total, error, updated_at}``, or null.

``pace_inputs`` (credits per day, free and sick days, the plan's constants) feeds the
app's port of the plan (``app/lib/src/pace_plan.dart``) -- the one place the
app does derive pace, for the week/month/any-day/simulation views, offline.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any, Final

import freedays

from book_guard import _indexjob
from book_guard import _photos as _photo_cache
from book_guard._bookindex import index_path
from book_guard._errlog import claude_outage
from book_guard._ledger import load as load_ledger
from book_guard._pace_inputs import pace_inputs
from book_guard._render import todo_lines
from book_guard._session_files import file_name
from book_guard._sessions import NEEDS_QUIZ
from book_guard._thumbs import thumb_name

if TYPE_CHECKING:
    from book_guard._paths import Paths
    from book_guard._state import SessionView, Snapshot

SCHEMA: Final = 1
_GALLERY: Final = 40


def _session(view: SessionView) -> dict[str, Any]:
    s = view.session
    return {
        "id": s.session_id,
        "start_page": s.start.page,
        "end_page": s.end.page,
        "check_page": s.check_page,
        "pages": s.pages,
        "minutes": s.minutes,
        "started_at": s.started_at.isoformat(),
        "ended_at": s.ended_at.isoformat(),
        "photo_start": s.start.taken.isoformat(),
        "photo_end": s.end.taken.isoformat(),
        "status": view.status,
        "book": view.book.title if view.book else "",
        "detail": f"sessions/{file_name(s.session_id)}",
        "retry": _retry(view),
    }


def _retry(view: SessionView) -> dict[str, Any] | None:
    """A failed summary waiting for its rewrite: what the grader said last."""
    last = view.last_verdict
    if last is None or view.status != NEEDS_QUIZ:
        return None
    return {
        "feedback": last.detail.get("feedback", ""),
        "summary": last.detail.get("summary", ""),
        "missing": [m for m in last.detail.get("missing", "").split("\n") if m],
        "graded_at": last.created_at,
    }


def _latest_page(snap: Snapshot) -> int | None:
    """The newest photographed page of the current book: where the reader is."""
    book = snap.book
    seen = [
        (v.session.end.taken, v.session.end.page)
        for v in snap.sessions
        if book and v.book and v.book.isbn == book.isbn
    ]
    if snap.open_start is not None:
        seen.append((snap.open_start.taken, snap.open_start.page))
    pages = [(taken, page) for taken, page in seen if page]
    return max(pages)[1] if pages else None


def _chapter(snap: Snapshot) -> dict[str, Any] | None:
    page = _latest_page(snap)
    found = snap.book.chapter_at(page) if snap.book and page else None
    if found is None or snap.book is None:
        return None
    number, chapter = found
    return {"number": number, "of": len(snap.book.chapters), "title": chapter.title}


def _photos(paths: Paths) -> list[dict[str, Any]]:
    """The newest photos, for the gallery: where to fetch them, what they were."""
    records = sorted(
        _photo_cache.load(paths.photos).values(),
        key=lambda r: r.taken_at or r.uploaded_at,
        reverse=True,
    )
    return [
        {
            "name": r.name,
            "file": f"processed/{r.sha[:12]}-{r.name}",
            "thumb": f"thumbs/{thumb_name(r.sha)}",
            "kind": r.kind,
            "page": r.page,
            "status": r.status,
            "reason": r.reason,
            "taken_at": r.taken_at or r.uploaded_at,
        }
        for r in records[:_GALLERY]
    ]


def to_json(paths: Paths, snap: Snapshot) -> dict[str, Any]:
    """Everything the app renders."""
    book = snap.book
    pace = snap.pace
    start = snap.open_start
    now = datetime.now(tz=UTC)
    outage = claude_outage(paths, now)
    return {
        "schema": SCHEMA,
        "generated_at": now.isoformat(),
        "today": snap.today.isoformat(),
        "locked": snap.locked,
        "reason": snap.reason,
        "sick_today": snap.sick_today,
        "book": None
        if book is None
        else {
            "isbn": book.isbn,
            "title": book.title,
            "author": book.author,
            "pages": book.pages,
            "has_file": index_path(paths, book.isbn).exists(),
            "chapters": [{"start": c.start, "title": c.title} for c in book.chapters],
            "chapter": _chapter(snap),
        },
        "pace": {
            "month": pace.month.isoformat()[:7],
            "target": pace.target,
            "pages": pace.pages,
            "required": pace.required,
            "behind": pace.behind,
            "carried_debt": pace.carried_debt,
            "carried_credit": pace.carried_credit,
            "finished_books": pace.finished_books,
            "pages_today": pace.pages_today,
            "passed_today": pace.passed_today,
            "days_left": pace.days_left,
            "debt_per_day": pace.ask.debt_per_day,
            "debt_days_left": pace.ask.debt_days,
            "debt_unplaced": pace.ask.debt_unplaced,
            "today_required": pace.ask.bonus_at,
            "today_quota": pace.ask.required,
            "bonus_today": pace.ask.bonus,
            "excused": pace.ask.excused,
            "daily": pace.ask.daily,
        },
        "open_start": None
        if start is None
        else {"page": start.page, "taken_at": start.taken.isoformat()},
        "todo": todo_lines(snap),
        "sessions": [_session(v) for v in snap.sessions],
        "escapes_left": snap.escapes_left,
        "photos": _photos(paths),
        "claude_down_since": None if outage is None else outage.since,
        "claude_down_until": None if outage is None else outage.until,
        "index_job": _indexjob.load(paths),
        "pace_inputs": pace_inputs(
            load_ledger(paths.ledger, paths.key_file),
            snap.today,
            freedays.is_free_day,
            snap.sick_days,
        ),
    }
