# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_atomic_json, _errors, _flock, _photos and _constants."""

from __future__ import annotations

from datetime import date
import json
import stat
from typing import TYPE_CHECKING

import pytest

from book_guard import _atomic_json, _constants, _flock, _photos
from book_guard._errors import CorruptFileError
from book_guard._photos import OK, REJECTED, PhotoRecord

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths


def test_write_json_creates_parent_and_is_readable(tmp_path: Path) -> None:
    target = tmp_path / "deep" / "dir" / "doc.json"
    _atomic_json.write_json(target, {"a": [1, 2]}, indent=2)
    assert json.loads(target.read_text(encoding="utf-8")) == {"a": [1, 2]}
    assert "\n  " in target.read_text(encoding="utf-8")
    assert [p.name for p in target.parent.iterdir()] == ["doc.json"]


def test_write_json_before_write_runs_on_temp_file(tmp_path: Path) -> None:
    target = tmp_path / "secret.json"
    seen: list[Path] = []

    def lock_down(temp: Path) -> None:
        assert temp != target
        assert temp.read_text(encoding="utf-8") == ""
        temp.chmod(0o600)
        seen.append(temp)

    _atomic_json.write_json(target, {"k": "v"}, before_write=lock_down)
    assert len(seen) == 1
    assert not seen[0].exists()
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
    assert json.loads(target.read_text(encoding="utf-8")) == {"k": "v"}


def test_write_json_replaces_existing(tmp_path: Path) -> None:
    target = tmp_path / "doc.json"
    target.write_text("old", encoding="utf-8")
    _atomic_json.write_json(target, [1])
    assert target.read_text(encoding="utf-8") == "[1]"


def test_write_text(tmp_path: Path) -> None:
    target = tmp_path / "sub" / "note.txt"
    _atomic_json.write_text(target, "hello\nworld")
    assert target.read_text(encoding="utf-8") == "hello\nworld"
    assert [p.name for p in target.parent.iterdir()] == ["note.txt"]


def test_corrupt_file_error_is_value_error() -> None:
    msg = "broken"
    with pytest.raises(ValueError, match=msg):
        raise CorruptFileError(msg)


def test_exclusive_lock_creates_lock_file(bg_paths: Paths) -> None:
    assert not bg_paths.data_dir.exists()
    with _flock.exclusive(bg_paths):
        assert (bg_paths.data_dir / "write.lock").exists()
    # Re-entrant across separate blocks: the lock was released.
    with _flock.exclusive(bg_paths):
        pass


def test_exclusive_releases_on_error(bg_paths: Paths) -> None:
    with pytest.raises(RuntimeError), _flock.exclusive(bg_paths):
        raise RuntimeError
    with _flock.exclusive(bg_paths):
        pass


def test_constants_are_consistent() -> None:
    assert date(2026, 10, 1) == _constants.GATE_START_DATE
    assert _constants.MONTHLY_PAGES > 0
    assert _constants.MAX_SESSION.total_seconds() == 6 * 3600
    assert "skipping" in _constants.ESCAPE_PHRASE


def _record(
    sha: str,
    taken: str,
    *,
    kind: str = "page",
    page: int | None = 1,
    isbn: str | None = None,
    status: str = OK,
    reason: str = "",
) -> PhotoRecord:
    return PhotoRecord(
        sha=sha,
        name=f"{sha}.jpg",
        taken_at=taken,
        uploaded_at=taken,
        kind=kind,
        page=page,
        isbn=isbn,
        status=status,
        reason=reason,
    )


def test_photos_load_missing_is_empty(tmp_path: Path) -> None:
    assert _photos.load(tmp_path / "none.json") == {}


def test_photos_load_rejects_non_dict(tmp_path: Path) -> None:
    target = tmp_path / "photos.json"
    target.write_text("[]", encoding="utf-8")
    with pytest.raises(CorruptFileError, match="not a photo cache"):
        _photos.load(target)


def test_photos_roundtrip_and_usable_pages(tmp_path: Path) -> None:
    target = tmp_path / "photos.json"
    records = {
        "b": _record("b", "2026-10-02T10:00:00+00:00", page=5),
        "a": _record("a", "2026-10-02T09:00:00+00:00", page=3),
        "c": _record("c", "2026-10-02T09:00:00+00:00", page=4),
        "x": _record("x", "", kind="other", page=None),
        "r": _record("r", "", status=REJECTED, reason="no exif"),
        "i": _record("i", "2026-10-01T09:00:00+00:00", kind="isbn", isbn="1"),
    }
    _photos.save(target, records)
    loaded = _photos.load(target)
    assert loaded == records
    usable = _photos.usable_pages(loaded)
    assert [r.sha for r in usable] == ["a", "c", "b"]
    assert all(r.status == OK for r in usable)
    assert usable[0].taken.hour == 9
