# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Widening a session's times from the CLI: signed, with a reason."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import TYPE_CHECKING

import pytest

from book_guard import _widen
from book_guard._cli import main
from book_guard._ledger import load
from book_guard._session_times import RETIME
from book_guard._sessions import NEEDS_QUIZ, TOO_FAST
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import T0, add_book, add_entry, rec, seed_photos

if TYPE_CHECKING:
    from book_guard._paths import Paths

# 2026-10-23: the phone lost the 10:0x start photo, so p. 252 was
# re-photographed after reading, 33 s before the p. 302 photo.
START, END = T0, T0 + timedelta(seconds=33)
READ_FROM = T0 - timedelta(minutes=54)


def _seed(paths: Paths) -> str:
    add_book(paths, pages=611)
    seed_photos(paths, rec("s", 252, START), rec("e", 253, END))
    (view,) = snapshot(paths).sessions
    assert view.status == TOO_FAST
    return view.session.session_id


def test_a_widened_start_reaches_the_session(bg_paths: Paths) -> None:
    sid = _seed(bg_paths)
    message = _widen.widen(bg_paths, sid, READ_FROM, None, "phone lost the start")
    assert message.endswith("(54 min)")
    (view,) = snapshot(bg_paths).sessions
    assert (view.status, view.session.started_at) == (NEEDS_QUIZ, READ_FROM)
    assert view.session.ended_at == END
    (row,) = load(bg_paths.ledger, bg_paths.key_file).of_kind(RETIME)
    assert row.detail["reason"] == "phone lost the start"


def test_an_end_can_move_too(bg_paths: Paths) -> None:
    sid = _seed(bg_paths)
    later = END + timedelta(minutes=5)
    _widen.widen(bg_paths, sid, READ_FROM, later, "late stop")
    (view,) = snapshot(bg_paths).sessions
    assert view.session.ended_at == later


@pytest.mark.parametrize(
    ("case", "error"),
    [
        (("nope", READ_FROM, "r"), "No such session."),
        ((None, READ_FROM, "  "), "A reason is required."),
        ((None, END, "r"), "The start must come before the end."),
        ((None, START - timedelta(seconds=10), "r"), "1 pages need at least"),
    ],
)
def test_refusals(
    bg_paths: Paths, case: tuple[str | None, datetime, str], error: str
) -> None:
    real = _seed(bg_paths)
    sid, start, reason = case
    with pytest.raises(_widen.WidenError, match=error):
        _widen.widen(bg_paths, sid or real, start, None, reason)


def test_once_per_session_and_never_after_grading(bg_paths: Paths) -> None:
    sid = _seed(bg_paths)
    _widen.widen(bg_paths, sid, READ_FROM, None, "r")
    with pytest.raises(_widen.WidenError, match="already retimed"):
        _widen.widen(bg_paths, sid, READ_FROM, None, "r")
    add_entry(bg_paths, sid, "credit", T0.date().isoformat(), 1)
    with pytest.raises(_widen.WidenError, match="already graded"):
        _widen.widen(bg_paths, sid, READ_FROM, None, "r")


def test_cli(bg_paths: Paths, capsys: pytest.CaptureFixture[str]) -> None:
    sid = _seed(bg_paths)
    argv = ["retime", sid, "--start", READ_FROM.isoformat(), "--reason", "lost"]
    assert main(argv) == 0
    assert "(54 min)" in capsys.readouterr().out
    assert main(argv) == 1
    assert "already retimed" in capsys.readouterr().err
