# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_manual_start: a start page set from the CLI, without a photo."""

from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

from book_guard import _manual_start, _mcp
from book_guard._cli import main
from book_guard._ledger import load
from book_guard._quiz import Verdict, record_verdict
from book_guard._render import status_lines
from book_guard._session_files import photo_ref
from book_guard._sessions import (
    NEEDS_CHECK,
    TOO_FAST,
    EbookSpan,
    Session,
    check_page_for,
)
from book_guard._state import snapshot
from book_guard._state_json import to_json
from book_guard.tests._flow_helpers import ISBN13, T0, add_book, rec, seed_photos

if TYPE_CHECKING:
    from book_guard._paths import Paths

AT = T0 + timedelta(hours=2)
NOW = AT + timedelta(minutes=10)


def _seed(paths: Paths) -> None:
    """A finished p. 200-259 session that stopped at T0 + 1 h."""
    add_book(paths, pages=611)
    seed_photos(
        paths,
        rec("s", 200, T0),
        rec("e", 259, T0 + timedelta(hours=1)),
    )


_REAL_NOW = _manual_start._now


@pytest.fixture(autouse=True)
def _clock(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(_manual_start, "_now", lambda: NOW)


def _start(paths: Paths, page: int = 260, at: datetime = AT, reason: str = "r") -> str:
    return _manual_start.start(paths, page=page, at=at, reason=reason)


def test_start_writes_a_signed_row_and_opens_the_session(bg_paths: Paths) -> None:
    _seed(bg_paths)
    line = _start(bg_paths, reason="app hid the camera")
    assert "p. 260" in line
    (row,) = load(bg_paths.ledger, bg_paths.key_file).of_kind(_manual_start.KIND)
    assert row.entry_id.startswith("start:")
    assert row.detail["page"] == "260"
    assert row.detail["isbn"] == ISBN13
    assert row.detail["reason"] == "app hid the camera"
    snap = snapshot(bg_paths)
    assert snap.open_start is not None
    assert (snap.open_start.page, snap.open_start.taken) == (260, AT)
    assert any("Reading since p. 260" in line for line in status_lines(snap))
    state = to_json(bg_paths, snap)["open_start"]
    assert state["page"] == 260
    assert state["manual"] is True
    assert state["sha"] == snap.open_start.sha
    assert datetime.fromisoformat(state["taken_at"]) == AT


def test_open_start_json_for_a_photo_start_is_not_manual(bg_paths: Paths) -> None:
    add_book(bg_paths, pages=611)
    seed_photos(bg_paths, rec("s", 200, T0))
    state = to_json(bg_paths, snapshot(bg_paths))["open_start"]
    assert state["manual"] is False


@pytest.mark.parametrize(
    ("page", "at", "error"),
    [
        (260, NOW + timedelta(minutes=1), "in the future"),
        (260, NOW - timedelta(days=1), "must be today"),
        (260, T0 + timedelta(minutes=30), "after the last session's stop"),
        (259, AT, "above p. 259"),
        (0, AT, "above p. 259"),
    ],
)
def test_refusals_write_nothing(
    bg_paths: Paths, page: int, at: datetime, error: str
) -> None:
    _seed(bg_paths)
    with pytest.raises(_manual_start.StartError, match=error):
        _start(bg_paths, page=page, at=at)
    assert not load(bg_paths.ledger, bg_paths.key_file).of_kind(_manual_start.KIND)


def test_refused_while_a_start_is_open(bg_paths: Paths) -> None:
    _seed(bg_paths)
    _start(bg_paths)
    with pytest.raises(_manual_start.StartError, match="already open"):
        _start(bg_paths, page=261, at=AT + timedelta(minutes=1))


def test_refused_while_a_photo_start_is_open(bg_paths: Paths) -> None:
    add_book(bg_paths, pages=611)
    seed_photos(bg_paths, rec("s", 200, T0))
    with pytest.raises(_manual_start.StartError, match="already open"):
        _start(bg_paths)


def test_reason_and_book_are_required(bg_paths: Paths) -> None:
    with pytest.raises(_manual_start.StartError, match="No book"):
        _start(bg_paths)
    _seed(bg_paths)
    with pytest.raises(_manual_start.StartError, match="reason"):
        _start(bg_paths, reason="  ")


def test_first_start_ever_needs_only_today(bg_paths: Paths) -> None:
    add_book(bg_paths, pages=611)
    _start(bg_paths, page=1)
    assert snapshot(bg_paths).open_start is not None


def test_page_floor() -> None:
    """Above a paper stop; an in-app session's end is the first page *not* read."""
    paper = Session(rec("a", 10, T0), rec("b", 20, T0 + timedelta(hours=1)), None)
    ebook = Session(
        rec("c", 10, T0),
        rec("d", 20, T0 + timedelta(hours=1)),
        None,
        ebook=EbookSpan("k", ISBN13, 0, 9),
    )
    assert _manual_start.page_floor(None) == 0
    assert _manual_start.page_floor(paper) == 20
    assert _manual_start.page_floor(ebook) == 19


def test_the_stop_photo_closes_it_and_is_judged_from_at(bg_paths: Paths) -> None:
    _seed(bg_paths)
    _start(bg_paths)
    stop = rec("stop", 290, AT + timedelta(minutes=31))  # 31 pages, 60 s each
    seed_photos(
        bg_paths, rec("s", 200, T0), rec("e", 259, T0 + timedelta(hours=1)), stop
    )
    snap = snapshot(bg_paths)
    assert snap.open_start is None
    session = snap.sessions[-1].session
    assert (session.start.page, session.end.page, session.pages) == (260, 290, 31)
    assert session.started_at == AT
    assert session.state == NEEDS_CHECK


def test_floor_counts_from_at(bg_paths: Paths) -> None:
    _seed(bg_paths)
    _start(bg_paths)
    base = [rec("s", 200, T0), rec("e", 259, T0 + timedelta(hours=1))]
    seed_photos(bg_paths, *base, rec("stop", 290, AT + timedelta(minutes=20)))  # 1200 s
    view = snapshot(bg_paths).sessions[-1]
    assert view.status == NEEDS_CHECK
    session = view.session
    assert 260 <= (session.check_page or 0) <= 290
    assert session.check_page == check_page_for(session.start, session.end)
    assert session.session_id.startswith("session:")
    assert [p.page for p in session.evidence] == [290]
    assert photo_ref("start", session.start) is None
    seed_photos(
        bg_paths, *base, rec("stop", 290, AT + timedelta(minutes=18))
    )  # 1080 s < 31*35
    assert snapshot(bg_paths).sessions[-1].status == TOO_FAST


def test_credit_row_says_the_start_was_manual(bg_paths: Paths) -> None:
    _seed(bg_paths)
    _start(bg_paths)
    base = [rec("s", 200, T0), rec("e", 259, T0 + timedelta(hours=1))]
    seed_photos(bg_paths, *base, rec("stop", 290, AT + timedelta(minutes=40)))
    snap = snapshot(bg_paths)
    manual, photo = snap.sessions[-1].session, snap.sessions[0].session
    verdict = Verdict(passed=True, feedback="ok", grader="claude:haiku")
    entry = record_verdict(bg_paths, snap.book, manual, verdict, "x" * 200)
    assert entry is not None
    assert entry.detail["start"] == "manual"
    other = record_verdict(bg_paths, snap.book, photo, verdict, "x" * 200)
    assert other is not None
    assert "start" not in other.detail


def test_cli(bg_paths: Paths, capsys: pytest.CaptureFixture[str]) -> None:
    _seed(bg_paths)
    at = AT.astimezone().replace(tzinfo=None).isoformat(timespec="minutes")
    argv = ["start", "--page", "260", "--at", at, "--reason", "r"]
    assert main(argv) == 0
    assert "p. 260" in capsys.readouterr().out
    assert main(argv) == 1
    assert "already open" in capsys.readouterr().err


def test_no_app_or_mcp_route() -> None:
    from book_guard import _app_handlers

    for module in (_app_handlers, _mcp):
        source = Path(str(module.__file__)).read_text(encoding="utf-8")
        assert "_manual_start" not in source
        assert "_manual_pages" not in source


def test_the_clock_is_local_and_aware() -> None:
    assert _REAL_NOW().tzinfo is not None
