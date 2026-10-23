# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""In-app reading: the PC's page map, served to the app, and its CLI."""

from __future__ import annotations

from datetime import timedelta
import json
from typing import TYPE_CHECKING

import pytest

from book_guard import (
    _ebook,
    _ebook_map,
    _embed,
)
from book_guard._actions import process
from book_guard._cli import main
from book_guard._ebook_text import served_text
from book_guard._photos import load as load_photos
from book_guard._state import snapshot
from book_guard._state_json import to_json
from book_guard.tests._ebook_flow import (
    PHOTO_PAGES,
    book_photos,
    map_book,
    text_sha,
)
from book_guard.tests._ebook_helpers import TEXT, middle, ocr
from book_guard.tests._flow_helpers import ISBN13, T0, add_book, rec, seed_photos
from book_guard.tests._index_helpers import drop

if TYPE_CHECKING:
    from book_guard._paths import Paths


@pytest.fixture
def mapped(bg_paths: Paths) -> Paths:
    """A registered book with its ebook indexed, five pages photographed."""
    return map_book(bg_paths)


def test_refresh_serves_the_text_and_the_map(mapped: Paths) -> None:
    text = (mapped.ebooks / f"{ISBN13}.txt").read_text(encoding="utf-8")
    assert text == served_text(TEXT)
    served = json.loads((mapped.ebooks / f"{ISBN13}.map.json").read_text("utf-8"))
    assert served["isbn"] == ISBN13
    assert served["text"] == f"ebooks/{ISBN13}.txt"
    assert served["text_sha"] == text_sha(text)
    assert served["chars"] == len(text)
    assert served["photos"] == len(PHOTO_PAGES)
    assert served["estimated"] is True
    loaded = _ebook.load_map(mapped, ISBN13)
    assert loaded is not None
    assert loaded.pages.page_at(middle(51)) == 51


def test_refresh_is_a_no_op_until_a_new_photo_arrives(mapped: Paths) -> None:
    served = mapped.ebooks / f"{ISBN13}.map.json"
    before = served.read_text("utf-8")
    assert not _ebook.refresh(mapped)
    records = load_photos(mapped.photos)
    seed_photos(
        mapped,
        *records.values(),
        rec("p110", 110, T0 + timedelta(days=9), text=ocr(110)),
    )
    assert _ebook.refresh(mapped)
    assert json.loads(served.read_text("utf-8"))["photos"] == len(PHOTO_PAGES) + 1
    assert served.read_text("utf-8") != before


def test_refresh_rewrites_a_text_the_share_lost(mapped: Paths) -> None:
    (mapped.ebooks / f"{ISBN13}.txt").unlink()
    assert _ebook.refresh(mapped)
    assert (mapped.ebooks / f"{ISBN13}.txt").exists()


def test_no_map_without_a_book_an_index_or_enough_photos(bg_paths: Paths) -> None:
    assert not _ebook.refresh(bg_paths)  # no book
    add_book(bg_paths, pages=120)
    assert not _ebook.refresh(bg_paths)  # no ebook attached
    _embed.build(bg_paths, ISBN13, TEXT, source="book.epub")
    seed_photos(bg_paths, *book_photos()[:2])
    assert not _ebook.refresh(bg_paths)  # two pages are not a map
    assert _ebook.load_map(bg_paths, ISBN13) is None
    assert _ebook.state_info(bg_paths, ISBN13) is None


def test_a_corrupt_private_map_reads_as_none(mapped: Paths) -> None:
    _ebook.map_file(mapped, ISBN13).write_text("{}", encoding="utf-8")
    assert _ebook.load_map(mapped, ISBN13) is None
    _ebook.map_file(mapped, ISBN13).write_text("not json", encoding="utf-8")
    assert _ebook.load_map(mapped, ISBN13) is None


def test_state_json_offers_the_reader(mapped: Paths) -> None:
    state = to_json(mapped, snapshot(mapped))
    ebook = state["book"]["ebook"]
    assert ebook["map"] == f"ebooks/{ISBN13}.map.json"
    assert ebook["text"] == f"ebooks/{ISBN13}.txt"
    assert ebook["text_sha"] == text_sha(served_text(TEXT))
    assert state["book"]["latest_page"] == 100  # the open start photo


def test_process_refreshes_the_map_after_the_photo_pass(bg_paths: Paths) -> None:
    add_book(bg_paths, pages=120)
    _embed.build(bg_paths, ISBN13, TEXT, source="book.epub")
    seed_photos(bg_paths, *book_photos())
    process(bg_paths, now=0.0)
    state = json.loads(bg_paths.state_file.read_text("utf-8"))
    assert state["book"]["ebook"]["photos"] == len(PHOTO_PAGES)


def test_the_cli_shows_the_map(
    mapped: Paths, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["ebook-map"]) == 0
    out = capsys.readouterr().out
    assert f"{len(PHOTO_PAGES)} photographed pages located" in out
    assert "leave-one-out error (pages)" in out


def test_the_cli_says_when_there_is_no_map(
    bg_paths: Paths, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["ebook-map"]) == 1
    assert "No page map" in capsys.readouterr().out


def test_a_map_of_one_located_photo_has_no_residuals(
    mapped: Paths, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(_ebook_map, "MIN_KNOTS", 2)
    seed_photos(mapped, *book_photos()[:2])
    _ebook.map_file(mapped, ISBN13).unlink()
    assert main(["ebook-map"]) == 0
    assert "[], RMS 0.00" in capsys.readouterr().out


def test_indexing_a_book_file_builds_its_map(
    bg_paths: Paths, capsys: pytest.CaptureFixture[str]
) -> None:
    add_book(bg_paths, pages=120)
    seed_photos(bg_paths, *book_photos())
    drop(bg_paths, "book.txt", TEXT)
    assert main(["index"]) == 0
    assert "in-app reader: page map ready" in capsys.readouterr().out
    assert _ebook.load_map(bg_paths, ISBN13) is not None
