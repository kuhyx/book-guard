# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The index job record, attach stages and crashes, and Retry (requeue)."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _attach, _indexjob
from book_guard._app_handlers import HANDLERS
from book_guard._booktext import BookTextError
from book_guard.tests._flow_helpers import add_book
from book_guard.tests._index_helpers import drop, fail

if TYPE_CHECKING:
    from book_guard._paths import Paths

Out = pytest.CaptureFixture[str]


# -- _indexjob ----------------------------------------------------------------


def test_job_load_missing_unreadable_and_not_a_dict(bg_paths: Paths) -> None:
    assert _indexjob.load(bg_paths) is None
    bg_paths.index_job.parent.mkdir(parents=True)
    bg_paths.index_job.write_text("{", encoding="utf-8")
    assert _indexjob.load(bg_paths) is None
    bg_paths.index_job.write_text("[]", encoding="utf-8")
    assert _indexjob.load(bg_paths) is None


def test_job_write_patches_a_published_state(bg_paths: Paths) -> None:
    _indexjob.write(bg_paths, "a.txt", "extracting")
    assert not bg_paths.state_file.exists()  # no stub state.json is created
    bg_paths.state_file.parent.mkdir(parents=True)
    bg_paths.state_file.write_text('{"schema": 1}', encoding="utf-8")
    _indexjob.write(bg_paths, "a.txt", "embedding", progress=(3, 9))
    state = json.loads(bg_paths.state_file.read_text(encoding="utf-8"))
    assert state["schema"] == 1
    assert state["index_job"]["stage"] == "embedding"
    assert (state["index_job"]["done"], state["index_job"]["total"]) == (3, 9)
    assert _indexjob.load(bg_paths) == state["index_job"]


def test_job_write_leaves_a_bad_state_alone(bg_paths: Paths) -> None:
    bg_paths.state_file.parent.mkdir(parents=True)
    for text in ("{", "[1]"):
        bg_paths.state_file.write_text(text, encoding="utf-8")
        _indexjob.write(bg_paths, "a.txt", "done")
        assert bg_paths.state_file.read_text(encoding="utf-8") == text
    assert (_indexjob.load(bg_paths) or {})["stage"] == "done"


def test_job_write_failure_is_logged(
    bg_paths: Paths, caplog: pytest.LogCaptureFixture
) -> None:
    bg_paths.data_dir.mkdir(parents=True)
    bg_paths.index_job.mkdir()  # a directory where the file goes
    _indexjob.write(bg_paths, "a.txt", "done")
    assert "could not record the index job" in caplog.text


def test_progress_throttles_middle_updates(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    clock = iter([100.0, 100.2, 101.5, 101.6])
    monkeypatch.setattr("book_guard._indexjob.time.monotonic", lambda: next(clock))
    writes: list[tuple[int, int]] = []

    def record(_paths: Paths, _file: str, _stage: str, **kw: Any) -> None:
        writes.append(kw["progress"])

    monkeypatch.setattr(_indexjob, "write", record)
    progress = _indexjob.Progress(bg_paths, "a.txt")
    for done in (0, 1, 2, 4):
        progress(done, 4)
    assert writes == [(0, 4), (2, 4), (4, 4)]


# -- _attach: stages, crashes, retry -----------------------------------------


def test_attach_records_done_and_failed_stages(bg_paths: Paths) -> None:
    add_book(bg_paths)
    _attach.attach(bg_paths, drop(bg_paths))
    job = _indexjob.load(bg_paths) or {}
    assert job["stage"] == "done"
    assert job["done"] == job["total"] > 0
    with pytest.raises(BookTextError):
        _attach.attach(bg_paths, drop(bg_paths, "x.exe"))
    job = _indexjob.load(bg_paths) or {}
    assert (job["stage"], job["file"]) == ("failed", "x.exe")
    assert job["error"].startswith("x.exe: ")


def test_attach_crash_is_recorded_then_raised(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    add_book(bg_paths)

    def boom(*_a: object, **_k: object) -> int:
        msg = "disk full"
        raise OSError(msg)

    monkeypatch.setattr(_attach, "build", boom)
    with pytest.raises(OSError, match="disk full"):
        _attach.attach(bg_paths, drop(bg_paths))
    job = _indexjob.load(bg_paths) or {}
    assert job["stage"] == "failed"
    assert job["error"] == "war.txt: indexing crashed (OSError: disk full)"


def test_requeue_moves_a_failed_file_back(bg_paths: Paths) -> None:
    fail(bg_paths)
    assert _attach.requeue(bg_paths, "bad.epub") == "bad.epub queued again"
    assert (bg_paths.books / "bad.epub").is_file()
    assert not (bg_paths.books / "failed" / "bad.epub.txt").exists()
    assert (_indexjob.load(bg_paths) or {})["stage"] == "uploaded"


def test_requeue_prefers_a_newer_upload(bg_paths: Paths) -> None:
    fail(bg_paths)
    drop(bg_paths, "bad.epub", "newer")
    assert "already queued" in _attach.requeue(bg_paths, "bad.epub")
    assert (bg_paths.books / "bad.epub").read_text(encoding="utf-8") == "newer"
    assert not (bg_paths.books / "failed" / "bad.epub").exists()


@pytest.mark.parametrize("name", ["", "../x.epub", "a/b.epub", ".hidden"])
def test_requeue_refuses_odd_names(bg_paths: Paths, name: str) -> None:
    with pytest.raises(BookTextError, match="is not a book file name"):
        _attach.requeue(bg_paths, name)


def test_requeue_needs_a_failed_file(bg_paths: Paths) -> None:
    with pytest.raises(BookTextError, match=r"no failed book file named a\.epub"):
        _attach.requeue(bg_paths, "a.epub")


def test_retry_book_request(bg_paths: Paths) -> None:
    fail(bg_paths)
    ok = HANDLERS["retry_book"](bg_paths, {"file": "bad.epub"})
    assert (ok.ok, ok.message) == (True, "bad.epub queued again")
    refused = HANDLERS["retry_book"](bg_paths, {"file": "gone.epub"})
    assert not refused.ok
    assert "no failed book file" in refused.message
