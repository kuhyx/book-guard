# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Narrowing a session's times: later start, earlier end, never wider."""

from __future__ import annotations

from datetime import timedelta
from typing import TYPE_CHECKING

from book_guard import _retime
from book_guard._session_times import apply_times, load_times, when
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import T0, add_book, add_entry, rec, seed_photos

if TYPE_CHECKING:
    from book_guard._paths import Paths

START, END = T0, T0 + timedelta(minutes=120)


def _seed(paths: Paths) -> str:
    """p. 51 -> 52 (one page, no check photo) over two hours."""
    add_book(paths, pages=406)
    seed_photos(paths, rec("s", 51, START), rec("e", 52, END))
    (view,) = snapshot(paths).sessions
    return view.session.session_id


def _iso(minutes: int) -> str:
    return (T0 + timedelta(minutes=minutes)).isoformat()


def test_a_later_start_and_earlier_end_are_kept(bg_paths: Paths) -> None:
    sid = _seed(bg_paths)
    response = _retime.set_times(
        bg_paths, {"session_id": sid, "start": _iso(70), "end": _iso(110)}
    )
    assert response.ok
    assert response.message.startswith("p. 51-52: ")
    assert response.message.endswith("(40 min)")
    (view,) = snapshot(bg_paths).sessions
    assert (view.session.minutes, view.session.started_at) == (
        40,
        START + timedelta(minutes=70),
    )
    # Only the start: the end stays the end photo's.
    _retime.set_times(bg_paths, {"session_id": sid, "start": _iso(10)})
    (view,) = snapshot(bg_paths).sessions
    assert view.session.ended_at == T0 + timedelta(minutes=110)


def test_times_never_widen_or_go_too_fast(bg_paths: Paths) -> None:
    sid = _seed(bg_paths)
    for body in (
        {"start": _iso(-5)},
        {"end": _iso(125)},
        {"start": _iso(90), "end": _iso(80)},
    ):
        response = _retime.set_times(bg_paths, {"session_id": sid, **body})
        assert response.message.startswith("Times must stay within the photos")
    assert _retime.set_times(bg_paths, {"session_id": "nope"}).message == (
        "No such session."
    )


def test_too_fast_is_refused(bg_paths: Paths) -> None:
    add_book(bg_paths, pages=406)
    seed_photos(bg_paths, rec("s", 51, START), rec("e", 104, END))
    (view,) = snapshot(bg_paths).sessions
    response = _retime.set_times(
        bg_paths, {"session_id": view.session.session_id, "start": _iso(100)}
    )
    assert response.message == "53 pages need at least 44 minutes."


def test_a_graded_session_keeps_its_times(bg_paths: Paths) -> None:
    sid = _seed(bg_paths)
    add_entry(bg_paths, sid, "credit", T0.date().isoformat(), 1)
    response = _retime.set_times(bg_paths, {"session_id": sid, "start": _iso(30)})
    assert response.message == "This session was already graded."


def test_stored_times_are_clamped_and_bad_files_ignored(bg_paths: Paths) -> None:
    sid = _seed(bg_paths)
    bg_paths.session_times.parent.mkdir(parents=True, exist_ok=True)
    bg_paths.session_times.write_text(
        f'{{"{sid}": {{"start": "{_iso(-30)}", "end": "not a time"}}, "x": 5}}',
        encoding="utf-8",
    )
    times = load_times(bg_paths.session_times)
    assert times[sid] == (T0 - timedelta(minutes=30), None)
    (view,) = snapshot(bg_paths).sessions
    assert view.session.started_at == START  # earlier than the photo: ignored
    bg_paths.session_times.write_text("[]", encoding="utf-8")
    assert load_times(bg_paths.session_times) == {}
    bg_paths.session_times.write_text("{cut", encoding="utf-8")
    assert load_times(bg_paths.session_times) == {}
    session = view.session
    apply_times(session, {sid: (None, END + timedelta(minutes=5))})
    assert session.ended_at == END  # later than the photo: ignored


def test_naive_times_are_local() -> None:
    moment = when("2026-10-03T13:40:00")
    assert moment is not None
    assert moment.tzinfo is not None
    assert when("") is None
    assert when(5) is None
