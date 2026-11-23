# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_accept: crediting a session by hand, without the grader."""

from __future__ import annotations

from datetime import timedelta
from typing import TYPE_CHECKING

import pytest

from book_guard import _accept
from book_guard._cli import main
from book_guard._ledger import load
from book_guard._sessions import NEEDS_CHECK, TOO_FAST
from book_guard._state import CREDITED, snapshot
from book_guard.tests._flow_helpers import T0, add_book, add_entry, rec, seed_photos

if TYPE_CHECKING:
    from book_guard._paths import Paths


def _seed(paths: Paths, seconds: int = 2290) -> str:
    """p. 29-88 (60 pages) in ``seconds``: the 2026-11-18 session by default."""
    add_book(paths, pages=611)
    seed_photos(paths, rec("s", 29, T0), rec("e", 88, T0 + timedelta(seconds=seconds)))
    (view,) = snapshot(paths).sessions
    return view.session.session_id


def test_accept_credits_without_check_page_or_summary(bg_paths: Paths) -> None:
    sid = _seed(bg_paths)
    assert snapshot(bg_paths).sessions[0].status == NEEDS_CHECK
    entry = _accept.accept(bg_paths, sid, "read it, skipped the check")
    assert (entry.entry_id, entry.kind, entry.amount) == (sid, "credit", 60)
    (row,) = load(bg_paths.ledger, bg_paths.key_file).verdicts()[sid]
    assert row.detail["graded"] == "0"
    assert row.detail["grader"] == "manual"
    assert row.detail["feedback"] == "accepted by hand: read it, skipped the check"
    assert snapshot(bg_paths).sessions[0].status == CREDITED


@pytest.mark.parametrize(
    ("seconds", "sid", "reason", "error"),
    [
        (2290, "nope", "r", "No such session."),
        (2290, None, "  ", "A reason is required."),
        (2099, None, "r", "too fast"),
    ],
)
def test_refusals(
    bg_paths: Paths, seconds: int, sid: str | None, reason: str, error: str
) -> None:
    real = _seed(bg_paths, seconds)
    with pytest.raises(_accept.AcceptError, match=error):
        _accept.accept(bg_paths, sid or real, reason)


def test_never_twice(bg_paths: Paths) -> None:
    sid = _seed(bg_paths)
    add_entry(bg_paths, sid, "credit", T0.date().isoformat(), 60)
    with pytest.raises(_accept.AcceptError, match="already credited"):
        _accept.accept(bg_paths, sid, "r")


def test_cli(bg_paths: Paths, capsys: pytest.CaptureFixture[str]) -> None:
    sid = _seed(bg_paths)
    assert main(["accept", sid, "--reason", "by hand"]) == 0
    assert "accepted p. 29-88: 60 pages" in capsys.readouterr().out
    assert main(["accept", sid, "--reason", "by hand"]) == 1
    assert "already credited" in capsys.readouterr().err


def test_too_fast_is_still_refused_by_the_cli(
    bg_paths: Paths, capsys: pytest.CaptureFixture[str]
) -> None:
    sid = _seed(bg_paths, 600)
    assert snapshot(bg_paths).sessions[0].status == TOO_FAST
    assert main(["accept", sid, "--reason", "r"]) == 1
    assert "too fast" in capsys.readouterr().err


def test_ignore_floor_credits_a_too_fast_session_marked_waived(
    bg_paths: Paths,
) -> None:
    sid = _seed(bg_paths, 600)
    assert snapshot(bg_paths).sessions[0].status == TOO_FAST
    entry = _accept.accept(bg_paths, sid, "owner grant", ignore_floor=True)
    assert (entry.kind, entry.amount) == ("credit", 60)
    (row,) = load(bg_paths.ledger, bg_paths.key_file).verdicts()[sid]
    assert row.detail["floor"] == "waived"
    assert row.detail["grader"] == "manual"
    assert snapshot(bg_paths).sessions[0].status == CREDITED


def test_ignore_floor_on_a_session_above_it_waives_nothing(bg_paths: Paths) -> None:
    sid = _seed(bg_paths)
    _accept.accept(bg_paths, sid, "r", ignore_floor=True)
    (row,) = load(bg_paths.ledger, bg_paths.key_file).verdicts()[sid]
    assert "floor" not in row.detail


def test_cli_ignore_floor(bg_paths: Paths, capsys: pytest.CaptureFixture[str]) -> None:
    sid = _seed(bg_paths, 600)
    assert main(["accept", sid, "--reason", "r", "--ignore-floor"]) == 0
    assert "accepted p. 29-88: 60 pages (speed floor waived)" in capsys.readouterr().out
