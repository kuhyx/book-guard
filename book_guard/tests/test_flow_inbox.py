# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The upload inbox: settle window, deferrals, duplicates and rejections."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
import os
from typing import TYPE_CHECKING

from PIL import Image
import pytest

from book_guard import _inbox, _photos
from book_guard._books import Chapter
from book_guard._claude import ClaudeUnavailableError
from book_guard._photo import PhotoFile
from book_guard._photos import REJECTED
from book_guard._vision import ISBN, PAGE, Reading
from book_guard.tests._flow_helpers import T0, sha

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

    from book_guard._paths import Paths

UPLOADED = T0 + timedelta(minutes=30)
NOW = UPLOADED.timestamp() + 60


def _drop(paths: Paths, name: str, *, mtime: float = UPLOADED.timestamp()) -> Path:
    paths.inbox.mkdir(parents=True, exist_ok=True)
    path = paths.inbox / name
    path.write_bytes(name.encode())
    os.utime(path, (mtime, mtime))
    return path


def _fake_open(
    monkeypatch: pytest.MonkeyPatch, photos: dict[str, PhotoFile | None]
) -> None:
    monkeypatch.setattr(_inbox, "open_photo", lambda path: photos[path.name])


def _photo(name: str, taken: datetime | None = T0) -> PhotoFile:
    return PhotoFile(sha=sha(name), taken_at=taken, jpeg_b64=name)


def _page_reader(page: int = 12) -> Callable[[Path, str], Reading]:
    return lambda _path, _b64: Reading(
        kind=PAGE, page_number=page, isbn=None, text="words"
    )


def test_missing_inbox_reads_nothing(bg_paths: Paths) -> None:
    result = _inbox.process_inbox(bg_paths, now=NOW)
    assert result == _inbox.InboxResult()
    assert _inbox.unsettled(bg_paths.inbox) == 0


def test_reads_a_page_and_files_it_away(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "a.jpg")
    _fake_open(monkeypatch, {"a.jpg": _photo("a")})
    result = _inbox.process_inbox(bg_paths, reader=_page_reader(), now=NOW)
    (record,) = result.read
    assert (record.kind, record.page, record.text) == (PAGE, 12, "words")
    assert record.uploaded_at == UPLOADED.isoformat()
    assert not (bg_paths.inbox / "a.jpg").exists()
    assert (bg_paths.processed / f"{sha('a')[:12]}-a.jpg").exists()
    assert _photos.load(bg_paths.photos)[sha("a")] == record
    assert result.new_isbns == []


def test_skips_unsettled_non_images_dirs_and_vanished(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "fresh.png", mtime=NOW - 1)
    _drop(bg_paths, "notes.txt")
    (bg_paths.inbox / "sub.jpg").mkdir()
    (bg_paths.inbox / "gone.jpg").symlink_to(bg_paths.inbox / "nowhere.jpg")
    _fake_open(monkeypatch, {})
    result = _inbox.process_inbox(bg_paths, reader=_page_reader(), now=NOW)
    assert result == _inbox.InboxResult()
    assert _inbox.unsettled(bg_paths.inbox, now=NOW) == 1


def test_file_vanished_between_listing_and_reading(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        _inbox, "_candidates", lambda inbox, _now: [inbox / "raced.jpg"]
    )
    assert _inbox.process_inbox(bg_paths, now=NOW) == _inbox.InboxResult()


def test_undecodable_is_deferred_and_left(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "half.webp")
    _fake_open(monkeypatch, {"half.webp": None})
    result = _inbox.process_inbox(bg_paths, now=NOW)
    assert result.deferred == ["half.webp"]
    assert (bg_paths.inbox / "half.webp").exists()


def test_duplicate_is_filed_without_reading(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "a.jpg")
    _fake_open(monkeypatch, {"a.jpg": _photo("a")})
    _inbox.process_inbox(bg_paths, reader=_page_reader(), now=NOW)
    _drop(bg_paths, "again.jpg")
    _fake_open(monkeypatch, {"again.jpg": _photo("a")})

    def no_read(_path: Path, _b64: str) -> Reading:
        raise AssertionError

    result = _inbox.process_inbox(bg_paths, reader=no_read, now=NOW)
    assert (result.duplicates, result.read) == (1, [])
    assert (bg_paths.processed / f"{sha('a')[:12]}-again.jpg").exists()


@pytest.mark.parametrize(
    ("taken", "reason", "taken_at"),
    [
        (None, "no EXIF capture time", ""),
        (
            UPLOADED - timedelta(hours=25),
            "uploaded more than 24h after it was taken",
            (UPLOADED - timedelta(hours=25)).isoformat(),
        ),
    ],
)
def test_rejections_are_recorded(
    bg_paths: Paths,
    monkeypatch: pytest.MonkeyPatch,
    taken: datetime | None,
    reason: str,
    taken_at: str,
) -> None:
    _drop(bg_paths, "r.jpg")
    _fake_open(monkeypatch, {"r.jpg": _photo("r", taken)})
    (record,) = _inbox.process_inbox(bg_paths, now=NOW).read
    assert (record.status, record.reason, record.kind) == (REJECTED, reason, "other")
    assert record.taken_at == taken_at


def test_claude_down_stops_the_pass(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "1.jpg", mtime=UPLOADED.timestamp() - 2)
    _drop(bg_paths, "2.jpg")
    _fake_open(monkeypatch, {"1.jpg": _photo("1"), "2.jpg": _photo("2")})
    calls: list[str] = []

    def down(_path: Path, b64: str) -> Reading:
        calls.append(b64)
        msg = "offline"
        raise ClaudeUnavailableError(msg)

    result = _inbox.process_inbox(bg_paths, reader=down, now=NOW)
    assert result.deferred == ["1.jpg"]
    assert calls == ["1"]
    assert (bg_paths.inbox / "1.jpg").exists()
    assert (bg_paths.inbox / "2.jpg").exists()
    assert not bg_paths.photos.exists()


def test_isbn_collection(bg_paths: Paths, monkeypatch: pytest.MonkeyPatch) -> None:
    _drop(bg_paths, "a.jpg", mtime=UPLOADED.timestamp() - 2)
    _drop(bg_paths, "b.jpg")
    _fake_open(monkeypatch, {"a.jpg": _photo("a"), "b.jpg": _photo("b")})
    readings = {
        "a": Reading(kind=ISBN, page_number=None, isbn="9780140449136", text=""),
        "b": Reading(kind=ISBN, page_number=None, isbn=None, text=""),
    }
    result = _inbox.process_inbox(
        bg_paths, reader=lambda _path, b64: readings[b64], now=NOW
    )
    assert result.new_isbns == ["9780140449136"]
    assert len(result.read) == 2


def test_real_jpeg_with_exif_default_clock(bg_paths: Paths) -> None:
    """End to end through the real decoder; ``now`` from the real clock."""
    bg_paths.inbox.mkdir(parents=True)
    taken = datetime.now(tz=UTC) - timedelta(minutes=10)
    image = Image.new("RGB", (32, 32), "white")
    exif = image.getexif()
    exif[0x0132] = taken.astimezone().strftime("%Y:%m:%d %H:%M:%S")
    path = bg_paths.inbox / "real.jpg"
    image.save(path, exif=exif)
    old = datetime.now(tz=UTC).timestamp() - 60
    os.utime(path, (old, old))
    (record,) = _inbox.process_inbox(bg_paths, reader=_page_reader(7)).read
    assert record.page == 7
    assert record.taken_at.startswith(taken.astimezone().strftime("%Y-%m-%dT%H:%M"))
    (bg_paths.inbox / "uploading.jpg").write_bytes(b"x")
    assert _inbox.unsettled(bg_paths.inbox) == 1  # real clock, just written


def test_contents_photo_is_read_as_chapters(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _drop(bg_paths, "toc-a.jpg")
    _drop(bg_paths, "toc-b.jpg", mtime=UPLOADED.timestamp() + 1)
    _fake_open(
        monkeypatch,
        {"toc-a.jpg": _photo("toc-a", taken=None), "toc-b.jpg": _photo("toc-b")},
    )
    found = {
        "toc-a": (Chapter(1, "One"), Chapter(30, "Two")),
        "toc-b": (),
    }
    result = _inbox.process_inbox(
        bg_paths, toc_reader=lambda _path, b64: found[b64], now=NOW
    )
    first, second = result.read
    assert (first.kind, first.taken_at, first.text) == ("toc", "", "1\tOne\n30\tTwo")
    assert second.taken_at == T0.isoformat()
    assert result.contents == [found["toc-a"]]
