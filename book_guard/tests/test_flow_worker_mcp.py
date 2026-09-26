# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The single-slot background worker and the read-only MCP tools."""

from __future__ import annotations

import runpy
import sys
import threading
from typing import TYPE_CHECKING

from mcp.server import MCPServer
import pytest

from book_guard import _mcp, _worker
from book_guard._embed import build
from book_guard._worker import OneJob
from book_guard.tests._flow_helpers import (
    ISBN13,
    LONG_TEXT,
    add_book,
    only_session,
    quiz_pair,
    seed_photos,
)

if TYPE_CHECKING:
    from book_guard._paths import Paths

WAIT = 5.0


def _wait_done(job: OneJob) -> None:
    future = job._future
    assert future is not None
    future.exception(timeout=WAIT)


def _busy(job: OneJob) -> bool:
    """Read ``busy`` through a call, so a type checker never narrows it."""
    return job.busy


def test_one_job_lifecycle() -> None:
    job = OneJob()
    gate = threading.Event()
    results: list[int] = []
    assert not _busy(job)
    assert job.finish_if_done() is False  # idle

    assert job.start(lambda: gate.wait(WAIT) and 42, results.append) is True
    assert _busy(job)
    assert job.start(lambda: 0, results.append) is False  # refused while busy
    assert job.finish_if_done() is False  # still running

    gate.set()
    _wait_done(job)
    assert job.finish_if_done() is True
    assert results == [42]
    assert not _busy(job)
    job.shutdown()


def test_one_job_reraises_on_the_caller() -> None:
    job = OneJob()

    def boom() -> None:
        msg = "model down"
        raise RuntimeError(msg)

    assert job.start(boom, lambda _r: None)
    _wait_done(job)
    with pytest.raises(RuntimeError, match="model down"):
        job.finish_if_done()
    assert not job.busy
    job.shutdown()


def test_default_completion_ignores_its_result() -> None:
    _worker._ignore(object())  # accepts anything, returns nothing


# -- MCP ----------------------------------------------------------------------


def test_get_status(bg_paths: Paths) -> None:
    add_book(bg_paths)
    status = _mcp.get_status()
    assert status["book"]["isbn"] == ISBN13
    assert status["schema"] == 1


def test_search_book_needs_a_book_and_a_file(bg_paths: Paths) -> None:
    error = {"error": "no book file attached (book-guard attach FILE)"}
    assert _mcp.search_book("war") == error
    add_book(bg_paths)
    assert _mcp.search_book("war") == error


@pytest.mark.parametrize(("top", "count"), [(0, 1), (3, 3), (99, 10)])
def test_search_book_finds_passages(bg_paths: Paths, top: int, count: int) -> None:
    add_book(bg_paths)
    build(bg_paths, ISBN13, LONG_TEXT, source="war.txt")
    found = _mcp.search_book("word5 sentence5.", top=top)
    assert found["book"] == "War -- Tol"
    passages = found["passages"]
    assert len(passages) == count
    first = passages[0]
    assert first["text"] == LONG_TEXT[first["offset"] : first["offset"] + 700]
    assert isinstance(first["score"], float)


def test_session_text(bg_paths: Paths) -> None:
    assert _mcp.session_text("session:none") == {"error": "no session 'session:none'"}
    records = quiz_pair()
    seed_photos(bg_paths, *records)
    sid = only_session(records).session_id
    assert _mcp.session_text(sid) == {
        "reason": "no book file attached",
        "scores": [],
        "text": "",
    }
    add_book(bg_paths)
    build(bg_paths, ISBN13, LONG_TEXT, source="war.txt")
    reply = _mcp.session_text(sid)
    assert reply["reason"] == (
        "a photographed page had too little legible text to anchor"
    )


def test_main_serves_stdio(monkeypatch: pytest.MonkeyPatch) -> None:
    ran: list[bool] = []
    monkeypatch.setattr(_mcp.mcp, "run", lambda: ran.append(True))
    _mcp.main()
    assert ran == [True]


def test_run_as_a_script(monkeypatch: pytest.MonkeyPatch) -> None:
    ran: list[str] = []
    monkeypatch.setattr(MCPServer, "run", lambda self: ran.append(self.name))
    monkeypatch.delitem(sys.modules, "book_guard._mcp")
    runpy.run_module("book_guard._mcp", run_name="__main__")
    assert ran == ["book-guard"]
