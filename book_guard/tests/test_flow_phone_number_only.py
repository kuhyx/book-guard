# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Only the phone's page number counts; an OCR miss becomes a page_truth row."""

from __future__ import annotations

from datetime import timedelta
import json
import os
from typing import TYPE_CHECKING

import pytest

from book_guard import _inbox, _page_truth
from book_guard._pagenum import Context
from book_guard._photo import PhotoFile
from book_guard._photo_context import Sidecar, sidecar_path
from book_guard._photos import NEEDS_NUMBER, OK, REJECTED, PhotoRecord
from book_guard._vision import ISBN, PAGE, Reading
from book_guard.tests._flow_helpers import T0, sha

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths

UPLOADED = T0 + timedelta(minutes=30)
NOW = UPLOADED.timestamp() + 60


def _drop(paths: Paths, name: str, note: dict[str, object] | None = None) -> Path:
    paths.inbox.mkdir(parents=True, exist_ok=True)
    path = paths.inbox / name
    path.write_bytes(name.encode())
    os.utime(path, (UPLOADED.timestamp(), UPLOADED.timestamp()))
    if note is not None:
        sidecar_path(path).write_text(json.dumps(note), encoding="utf-8")
    return path


def _fake_open(monkeypatch: pytest.MonkeyPatch, name: str) -> None:
    photo = PhotoFile(sha=sha(name), taken_at=T0, jpeg_b64=name)
    monkeypatch.setattr(_inbox, "open_photo", lambda _path: photo)


def _never(*_args: object) -> Reading:
    msg = "the PC must not read this photo's page number"
    raise AssertionError(msg)


def _phone_reader(_path: Path, context: Context) -> Reading:
    return Reading(PAGE, context.hint, None, "words")


def _manifest(paths: Paths) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = json.loads(
        (paths.page_truth_dir / "manifest.json").read_text("utf-8")
    )
    return rows


def _errors(paths: Paths) -> list[dict[str, object]]:
    lines = paths.error_log.read_text(encoding="utf-8").splitlines()
    return [json.loads(line) for line in lines]


def _pass(paths: Paths) -> PhotoRecord:
    result = _inbox.process_inbox(
        paths, reader=_phone_reader, barcode=lambda _p: None, now=NOW
    )
    (record,) = result.read
    return record


def test_no_number_is_rejected_and_never_read(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "start_a.jpg")
    _fake_open(monkeypatch, "start_a.jpg")
    result = _inbox.process_inbox(
        bg_paths, reader=_never, barcode=lambda _p: None, now=NOW
    )
    (record,) = result.read
    assert (record.status, record.reason) == (REJECTED, NEEDS_NUMBER)
    assert (record.kind, record.page) == ("other", None)
    assert (bg_paths.processed / f"{sha('start_a.jpg')[:12]}-start_a.jpg").exists()
    (entry,) = _errors(bg_paths)
    assert (entry["photo"], entry["error"]) == ("start_a.jpg", NEEDS_NUMBER)


def test_box_only_note_is_still_no_number(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "stop_a.jpg", {"box": [1, 2, 30, 40]})
    _fake_open(monkeypatch, "stop_a.jpg")
    result = _inbox.process_inbox(
        bg_paths, reader=_never, barcode=lambda _p: None, now=NOW
    )
    (record,) = result.read
    assert record.reason == NEEDS_NUMBER


def test_barcode_photo_without_number_is_an_isbn(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "a.jpg")
    _fake_open(monkeypatch, "a.jpg")
    result = _inbox.process_inbox(
        bg_paths, reader=_never, barcode=lambda _p: "9780140449136", now=NOW
    )
    (record,) = result.read
    assert (record.kind, record.isbn, record.status) == (ISBN, "9780140449136", OK)
    assert result.new_isbns == ["9780140449136"]


def test_ocr_correction_logs_and_files_a_truth_row(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "start_a.jpg", {"page": 29, "ocr_page": 2})
    _fake_open(monkeypatch, "start_a.jpg")
    record = _pass(bg_paths)
    assert (record.page, record.status) == (29, OK)
    (entry,) = _errors(bg_paths)
    assert entry["error"] == _page_truth.OCR_CORRECTED
    assert (entry["photo"], entry["ocr_page"], entry["page"]) == ("start_a.jpg", 2, 29)
    filed = f"{sha('start_a.jpg')[:12]}-start_a.jpg"
    (row,) = _manifest(bg_paths)
    assert (row["file"], row["page"], row["ocr_page"]) == (filed, 29, 2)
    assert row["context"] == {}
    assert str(row["why"]).startswith("2026-")
    assert (bg_paths.page_truth_dir / filed).read_bytes() == b"start_a.jpg"


def test_row_keeps_the_context_and_other_rows(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    bg_paths.page_truth_dir.mkdir(parents=True)
    old = [{"file": "x.jpg", "context": {}, "page": 1}]
    (bg_paths.page_truth_dir / "manifest.json").write_text(json.dumps(old), "utf-8")
    _drop(bg_paths, "check19_a.jpg", {"page": 19, "ocr_page": 18})
    _fake_open(monkeypatch, "check19_a.jpg")
    _pass(bg_paths)
    first, second = _manifest(bg_paths)
    assert first == old[0]
    assert second["context"] == {"expected": 19}


def test_the_same_photo_twice_is_one_row(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    for _ in range(2):
        _drop(bg_paths, "start_a.jpg", {"page": 29, "ocr_page": 2})
        _fake_open(monkeypatch, "start_a.jpg")
        bg_paths.photos.unlink(missing_ok=True)  # the photo cache was lost
        _pass(bg_paths)
    assert len(_manifest(bg_paths)) == 1


@pytest.mark.parametrize("note", [{"page": 29, "ocr_page": 29}, {"page": 29}])
def test_agreeing_or_absent_ocr_files_nothing(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, note: dict[str, object]
) -> None:
    _drop(bg_paths, "start_a.jpg", note)
    _fake_open(monkeypatch, "start_a.jpg")
    assert _pass(bg_paths).status == OK
    assert not bg_paths.page_truth_dir.exists()
    assert not bg_paths.error_log.exists()


def test_ocr_guess_without_a_number_is_no_correction(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "start_a.jpg", {"ocr_page": 2})
    _fake_open(monkeypatch, "start_a.jpg")
    result = _inbox.process_inbox(
        bg_paths, reader=_never, barcode=lambda _p: None, now=NOW
    )
    assert [r.reason for r in result.read] == [NEEDS_NUMBER]
    assert not bg_paths.page_truth_dir.exists()


def test_truth_failure_logs_and_never_blocks_the_photo(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    def broken(*_args: object, **_kwargs: object) -> None:
        msg = "disk full"
        raise OSError(msg)

    monkeypatch.setattr(_page_truth, "write_json", broken)
    _drop(bg_paths, "start_a.jpg", {"page": 29, "ocr_page": 2})
    _fake_open(monkeypatch, "start_a.jpg")
    record = _pass(bg_paths)
    assert (record.page, record.status) == (29, OK)
    assert (bg_paths.processed / f"{sha('start_a.jpg')[:12]}-start_a.jpg").exists()
    kinds = [e["error"] for e in _errors(bg_paths)]
    assert kinds == [_page_truth.OCR_CORRECTED, _page_truth.TRUTH_FAILED]


@pytest.mark.parametrize("content", ["{not json", '{"file": "x"}'])
def test_a_broken_manifest_is_left_alone(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, content: str
) -> None:
    bg_paths.page_truth_dir.mkdir(parents=True)
    manifest = bg_paths.page_truth_dir / "manifest.json"
    manifest.write_text(content, encoding="utf-8")
    _drop(bg_paths, "start_a.jpg", {"page": 29, "ocr_page": 2})
    _fake_open(monkeypatch, "start_a.jpg")
    _pass(bg_paths)
    assert manifest.read_text(encoding="utf-8") == content
    assert _errors(bg_paths)[-1]["error"] == _page_truth.TRUTH_FAILED


def test_a_guess_with_no_corrected_page_files_nothing(
    bg_paths: Paths, tmp_path: Path
) -> None:
    photo = tmp_path / "a.jpg"
    photo.write_bytes(b"x")
    _page_truth.note_ocr_miss(bg_paths, photo, sha("a"), Context(), Sidecar(ocr_page=2))
    assert not bg_paths.page_truth_dir.exists()
