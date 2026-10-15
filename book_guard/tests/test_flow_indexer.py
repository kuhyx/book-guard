# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The background index run: queueing, the unit kick, the lock, the CLI."""

from __future__ import annotations

import subprocess
from typing import TYPE_CHECKING

import pytest

from book_guard import _cli, _indexer, _indexjob
from book_guard.tests._flow_helpers import LONG_TEXT, add_book
from book_guard.tests._index_helpers import drop

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths

Out = pytest.CaptureFixture[str]


# -- _indexer -----------------------------------------------------------------


def test_lock_is_exclusive(bg_paths: Paths) -> None:
    with _indexer.index_lock(bg_paths) as first:
        assert first
        with _indexer.index_lock(bg_paths) as second:
            assert not second
        assert _indexer.run_index(bg_paths) is None


def test_queued_and_mark_queued(bg_paths: Paths) -> None:
    assert _indexer.queued(bg_paths) == []
    assert not _indexer.mark_queued(bg_paths)
    drop(bg_paths, "b.txt")
    drop(bg_paths, "a.PDF")
    drop(bg_paths, "notes.doc")
    (bg_paths.books / "dir.txt").mkdir()
    assert [p.name for p in _indexer.queued(bg_paths)] == ["a.PDF", "b.txt"]
    assert _indexer.mark_queued(bg_paths)
    job = _indexjob.load(bg_paths) or {}
    assert (job["file"], job["stage"]) == ("a.PDF", "uploaded")
    stamp = job["updated_at"]
    assert _indexer.mark_queued(bg_paths)  # same file, same stage: untouched
    assert (_indexjob.load(bg_paths) or {})["updated_at"] == stamp


def test_mark_queued_leaves_a_running_job_and_a_held_lock(bg_paths: Paths) -> None:
    drop(bg_paths)
    _indexjob.write(bg_paths, "other.txt", "embedding")
    assert _indexer.mark_queued(bg_paths)
    assert (_indexjob.load(bg_paths) or {})["file"] == "other.txt"
    _indexjob.write(bg_paths, "other.txt", "done")
    with _indexer.index_lock(bg_paths):
        assert _indexer.mark_queued(bg_paths)
    assert (_indexjob.load(bg_paths) or {})["stage"] == "done"


def test_kick_in_the_sandbox_does_nothing(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("BOOK_GUARD_ROOT", str(tmp_path))
    _indexer.kick()  # conftest's systemctl stub would raise if it ran


def test_kick_without_systemctl(caplog: pytest.LogCaptureFixture) -> None:
    _indexer.kick()
    assert "no systemctl" in caplog.text


@pytest.mark.parametrize(("code", "logged"), [(0, False), (1, True)])
def test_kick_starts_the_unit_without_waiting(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
    *,
    code: int,
    logged: bool,
) -> None:
    calls: list[list[str]] = []

    def run(cmd: list[str], **_kw: object) -> subprocess.CompletedProcess[str]:
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, code, "", "unit not found")

    monkeypatch.setattr("book_guard._indexer.shutil.which", lambda _n: "/bin/sc")
    monkeypatch.setattr("book_guard._indexer.subprocess.run", run)
    _indexer.kick()
    assert calls == [["/bin/sc", "--user", "start", "--no-block", _indexer.INDEX_UNIT]]
    assert ("could not start" in caplog.text) is logged


def test_run_index_drains_files_dropped_mid_run(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    batches = iter([["one"], ["two"], []])
    monkeypatch.setattr(_indexer, "attach_dropped", lambda _p: next(batches))
    assert _indexer.run_index(bg_paths) == ["one", "two"]


def test_process_marks_and_kicks_but_never_indexes(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    add_book(bg_paths)
    drop(bg_paths)
    kicked: list[bool] = []
    monkeypatch.setattr("book_guard._actions.kick", lambda: kicked.append(True))
    _cli.main(["process"])
    assert kicked == [True]
    assert (bg_paths.books / "war.txt").exists()  # photos first: not indexed
    assert (_indexjob.load(bg_paths) or {})["stage"] == "uploaded"


# -- CLI ----------------------------------------------------------------------


def test_cli_index(bg_paths: Paths, capsys: Out) -> None:
    add_book(bg_paths)
    drop(bg_paths)
    assert _cli.main(["index"]) == 0
    assert capsys.readouterr().out.startswith("Attached war.txt:")
    with _indexer.index_lock(bg_paths):
        assert _cli.main(["index"]) == 0
        assert "another index run is going" in capsys.readouterr().out


def test_cli_attach_waits_for_an_index_run(
    bg_paths: Paths, tmp_path: Path, capsys: Out
) -> None:
    add_book(bg_paths)
    book = tmp_path / "war.txt"
    book.write_text(LONG_TEXT, encoding="utf-8")
    with _indexer.index_lock(bg_paths):
        assert _cli.main(["attach", str(book)]) == 1
    assert "an index run is going" in capsys.readouterr().out
