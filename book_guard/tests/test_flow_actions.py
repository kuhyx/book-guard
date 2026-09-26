# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The shared operations: a processing pass, the escape hatch, next quiz."""

from __future__ import annotations

from datetime import datetime, timedelta
import shutil
import subprocess
import time
from typing import TYPE_CHECKING, Any

from book_guard import _actions, _ledger
from book_guard._constants import ESCAPE_PHRASE, UPLOAD_SETTLE_SECONDS
from book_guard._inbox import InboxResult
from book_guard._ledger import ESCAPE
from book_guard.tests._flow_helpers import (
    ISBN13,
    T0,
    add_escape,
    only_session,
    quiz_pair,
    rec,
    seed_photos,
)

if TYPE_CHECKING:
    import pytest

    from book_guard._paths import Paths


class _Inbox:
    """Stands in for ``process_inbox``: hands out prepared results in order."""

    def __init__(self, *results: InboxResult) -> None:
        self.results = list(results)
        self.calls: list[dict[str, Any]] = []

    def __call__(self, _paths: Paths, **kwargs: Any) -> InboxResult:
        self.calls.append(kwargs)
        return self.results.pop(0) if self.results else InboxResult()


def _record(name: str = "p") -> Any:
    return rec(name, 10, T0)


def _notifier(monkeypatch: pytest.MonkeyPatch) -> list[list[str]]:
    sent: list[list[str]] = []
    monkeypatch.setattr(shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(subprocess, "run", lambda argv, **_k: sent.append(argv))
    return sent


def test_process_quiet_pass_does_not_notify(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    sent = _notifier(monkeypatch)
    inbox = _Inbox()
    monkeypatch.setattr(_actions, "process_inbox", inbox)
    monkeypatch.setattr(_actions, "unsettled", None)  # never consulted with now=
    result, snap = _actions.process(bg_paths, now=123.0)
    assert result == InboxResult()
    assert inbox.calls == [{"now": 123.0}]
    assert sent == []
    assert bg_paths.next_file.exists()
    assert snap.book is None


def test_process_reads_registers_and_notifies(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    sent = _notifier(monkeypatch)
    monkeypatch.setattr(
        _actions,
        "process_inbox",
        _Inbox(InboxResult(read=[_record()], new_isbns=[ISBN13])),
    )
    registered: list[str] = []

    def register_isbn(_paths: Paths, isbn: str) -> str:
        registered.append(isbn)
        return "ok"

    monkeypatch.setattr(_actions, "register_isbn", register_isbn)
    result, _snap = _actions.process(bg_paths, settle_wait=False)
    assert registered == [ISBN13]
    assert len(result.read) == 1
    (argv,) = sent
    assert argv[:2] == ["/usr/bin/notify-send", "book-guard"]
    assert "No book registered" in argv[2]


def test_notify_skipped_headless_or_empty(monkeypatch: pytest.MonkeyPatch) -> None:
    _actions._notify(["headless: which() is None in tests"])
    sent = _notifier(monkeypatch)
    _actions._notify([])
    assert sent == []


def test_process_waits_for_settling_uploads(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    first = InboxResult(read=[_record("a")], duplicates=1, deferred=["x.jpg"])
    later = InboxResult(
        read=[_record("b")], duplicates=2, deferred=["y.jpg"], new_isbns=[]
    )
    inbox = _Inbox(first, later)
    monkeypatch.setattr(_actions, "process_inbox", inbox)
    pending = iter([1, 0])
    monkeypatch.setattr(_actions, "unsettled", lambda _inbox: next(pending))
    slept: list[float] = []
    monkeypatch.setattr(time, "sleep", slept.append)
    result, _snap = _actions.process(bg_paths)
    assert slept == [UPLOAD_SETTLE_SECONDS]
    assert inbox.calls == [{"now": None}, {}]
    assert [r.name for r in result.read] == ["a.jpg", "b.jpg"]
    assert (result.duplicates, result.deferred) == (3, ["y.jpg"])


def test_process_gives_up_waiting_after_the_cap(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(_actions, "process_inbox", _Inbox())
    monkeypatch.setattr(_actions, "unsettled", lambda _inbox: 1)
    slept: list[float] = []
    monkeypatch.setattr(time, "sleep", slept.append)
    _actions.process(bg_paths)
    assert sum(slept) == _actions._SETTLE_WAIT_MAX


def _today() -> str:
    return datetime.now().astimezone().date().isoformat()


def test_escape_needs_the_exact_phrase(bg_paths: Paths) -> None:
    assert _actions.escape_today(bg_paths, "let me go") == (
        f'Type exactly: "{ESCAPE_PHRASE}"'
    )
    assert not bg_paths.ledger.exists()


def test_escape_spends_one(bg_paths: Paths) -> None:
    typed = "  " + ESCAPE_PHRASE.replace(" ", "   \n") + " "
    assert _actions.escape_today(bg_paths, typed) is None
    (entry,) = _ledger.load(bg_paths.ledger, bg_paths.key_file).of_kind(ESCAPE)
    assert (entry.entry_id, entry.day) == (f"escape:{_today()}", _today())


def test_escape_refused_when_none_left(bg_paths: Paths) -> None:
    month = _today()[:7]
    add_escape(bg_paths, f"{month}-01")
    add_escape(bg_paths, f"{month}-02")
    assert _actions.escape_today(bg_paths, ESCAPE_PHRASE) == (
        "No escapes left this month."
    )


def test_next_quiz(bg_paths: Paths) -> None:
    assert _actions.next_quiz(bg_paths) is None
    older = quiz_pair("old", T0)
    newer = quiz_pair("new", T0 + timedelta(hours=1))
    seed_photos(bg_paths, *older, *newer)
    first = _actions.next_quiz(bg_paths)
    assert first is not None
    assert first.session.session_id == only_session(older).session_id
    wanted = only_session(newer).session_id
    picked = _actions.next_quiz(bg_paths, session_id=wanted)
    assert picked is not None
    assert picked.session.session_id == wanted
    assert _actions.next_quiz(bg_paths, session_id="session:none") is None
