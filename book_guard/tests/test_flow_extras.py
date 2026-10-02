# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Chapters, contents merging, thumbnails and per-session detail files."""

from __future__ import annotations

from datetime import timedelta
import json
from typing import TYPE_CHECKING

from PIL import Image

from book_guard import _actions, _books, _ledger, _session_files, _state_json, _thumbs
from book_guard._books import Chapter
from book_guard._inbox import InboxResult
from book_guard._ledger import BOOK, CREDIT, Entry
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import (
    ISBN13,
    T0,
    add_book,
    add_entry,
    only_session,
    quiz_pair,
    rec,
    seed_photos,
)

if TYPE_CHECKING:
    from pathlib import Path

    import pytest

    from book_guard._paths import Paths


def test_chapter_at_and_normalise() -> None:
    book = _books.Book("1", "T", "", 300, T0, (Chapter(1, "A"), Chapter(30, "B")))
    assert book.chapter_at(29) == (1, Chapter(1, "A"))
    assert book.chapter_at(30) == (2, Chapter(30, "B"))
    assert _books.Book("1", "T", "", 300, T0).chapter_at(5) is None
    rows = [[30, "B"], [1, "A"], [1, "A again"], [0, "zero"], [5, " "], [2], "x"]
    assert _books.normalise_chapters(rows) == (Chapter(1, "A again"), Chapter(30, "B"))
    assert _books.normalise_chapters("nope") == ()


def test_unreadable_chapters_in_the_ledger(bg_paths: Paths) -> None:
    entry = Entry(
        entry_id="book:x",
        kind=BOOK,
        day="2026-10-02",
        detail={"isbn": "1", "title": "T", "author": "", "pages": "", "chapters": "{"},
        created_at=T0.isoformat(),
    )
    _ledger.append(bg_paths.ledger, bg_paths.key_file, entry)
    (book,) = _books.all_books(_ledger.load(bg_paths.ledger, bg_paths.key_file))
    assert book.chapters == ()


def test_re_registering_keeps_the_contents(bg_paths: Paths) -> None:
    add_book(bg_paths)
    assert (
        _actions.add_chapters(bg_paths, (Chapter(30, "B"),)) == "War -- Tol: 1 chapters"
    )
    assert (
        _actions.add_chapters(bg_paths, (Chapter(1, "A"),)) == "War -- Tol: 2 chapters"
    )
    add_book(bg_paths, pages=320)  # same ISBN, e.g. a page fix: chapters stay
    book = _books.current(_ledger.load(bg_paths.ledger, bg_paths.key_file))
    assert book is not None
    assert (book.pages, book.chapters) == (320, (Chapter(1, "A"), Chapter(30, "B")))
    add_book(bg_paths, isbn="9788368380002")  # another book starts empty
    other = _books.current(_ledger.load(bg_paths.ledger, bg_paths.key_file))
    assert other is not None
    assert other.chapters == ()


def test_contents_without_a_book(bg_paths: Paths) -> None:
    assert _actions.add_chapters(bg_paths, (Chapter(1, "A"),)).startswith(
        "contents photo read, but no book"
    )


def test_process_merges_contents(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    add_book(bg_paths)
    found = InboxResult(contents=[(Chapter(5, "Five"),)])
    monkeypatch.setattr(_actions, "process_inbox", lambda _paths, now: found)
    _actions.process(bg_paths, settle_wait=False)
    book = _books.current(_ledger.load(bg_paths.ledger, bg_paths.key_file))
    assert book is not None
    assert book.chapters == (Chapter(5, "Five"),)


def test_current_chapter_follows_the_latest_page(bg_paths: Paths) -> None:
    add_book(bg_paths)
    _actions.add_chapters(bg_paths, (Chapter(10, "Ten"), Chapter(60, "Sixty")))
    seed_photos(bg_paths, *quiz_pair("a", T0), rec("lone", 70, T0 + timedelta(hours=3)))
    snap = snapshot(bg_paths)
    assert _state_json.to_json(bg_paths, snap)["book"]["chapter"] == {
        "number": 2,
        "of": 2,
        "title": "Sixty",
    }


def test_no_chapter_before_the_first(bg_paths: Paths) -> None:
    add_book(bg_paths)
    _actions.add_chapters(bg_paths, (Chapter(900, "Late"),))
    seed_photos(bg_paths, *quiz_pair("a", T0))
    assert _state_json.to_json(bg_paths, snapshot(bg_paths))["book"]["chapter"] is None


def _image(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (1200, 900), "white").save(path)
    return path


def test_thumbnails(tmp_path: Path) -> None:
    processed, thumbs = tmp_path / "processed", tmp_path / "thumbs"
    _thumbs.backfill(processed, thumbs)  # no dir yet: nothing to do
    _image(processed / "abcdefabcdef-start_x.jpg")
    (processed / "sub").mkdir()
    _thumbs.backfill(processed, thumbs)
    thumb = thumbs / "abcdefabcdef.jpg"
    with Image.open(thumb) as small:
        assert max(small.size) == _thumbs.THUMB_EDGE
    stamp = thumb.stat().st_mtime_ns
    _thumbs.make_thumb(processed / "abcdefabcdef-start_x.jpg", thumbs)
    assert thumb.stat().st_mtime_ns == stamp  # existing thumbnails are kept


def test_broken_photo_gets_no_thumbnail(tmp_path: Path) -> None:
    bad = tmp_path / "123456789012-bad.jpg"
    bad.write_bytes(b"nope")
    _thumbs.make_thumb(bad, tmp_path / "thumbs")
    assert not (tmp_path / "thumbs" / "123456789012.jpg").exists()


def test_session_files(bg_paths: Paths, monkeypatch: pytest.MonkeyPatch) -> None:
    add_book(bg_paths)
    pair = quiz_pair("a", T0)
    seed_photos(bg_paths, *pair)
    session_id = only_session(pair).session_id
    add_entry(bg_paths, session_id, CREDIT, "2026-10-05", 10)
    snap = snapshot(bg_paths)
    _session_files.write_session_files(bg_paths, snap)
    target = bg_paths.sessions / _session_files.file_name(session_id)
    doc = json.loads(target.read_text("utf-8"))
    assert [p["role"] for p in doc["photos"]] == ["start", "end"]
    assert doc["book"] == "War"
    assert doc["status"] == "credited"
    stamp = target.stat().st_mtime_ns
    _session_files.write_session_files(bg_paths, snap)
    assert target.stat().st_mtime_ns == stamp  # unchanged: not rewritten

    def refuse(*_a: object, **_k: object) -> None:
        msg = "disk full"
        raise OSError(msg)

    target.write_text("{}", encoding="utf-8")
    monkeypatch.setattr(_session_files, "write_json", refuse)
    _session_files.write_session_files(bg_paths, snap)  # logged, not raised
    assert ISBN13 not in target.read_text("utf-8")
