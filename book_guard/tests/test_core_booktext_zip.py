# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_booktext: FBZ / HTMLZ / TXTZ (zipfile) and the dropped formats."""

from __future__ import annotations

from pathlib import Path

import pytest

from book_guard import _booktext
from book_guard._booktext import BookTextError
from book_guard.tests import _booktext_helpers as helpers
from book_guard.tests._booktext_helpers import LONG, make_zip


@pytest.fixture
def fake_run(monkeypatch: pytest.MonkeyPatch) -> helpers.FakeRun:
    fake = helpers.FakeRun()
    monkeypatch.setattr(_booktext, "_run", fake)
    return fake


def test_fbz_hands_the_inner_fb2_to_pandoc(
    tmp_path: Path, fake_run: helpers.FakeRun
) -> None:
    path = make_zip(
        tmp_path / "book.fbz", {"cover.jpg": b"x", "b.FB2": b"<FictionBook/>"}
    )
    assert _booktext.extract(path) == LONG
    command = fake_run.commands[0]
    assert command[:7] == [
        "pandoc",
        "--sandbox",
        "-f",
        "fb2",
        "-t",
        "plain",
        "--wrap=none",
    ]
    assert command[7].endswith("b.FB2")
    assert not Path(command[7]).exists()  # temp dir cleaned up


def test_htmlz_strips_every_html_member(tmp_path: Path) -> None:
    body = "".join(f"<p>{LONG[:500]} &amp; more</p>" for _ in range(50))
    path = make_zip(
        tmp_path / "book.htmlz",
        {"style.css": b"p{}", "index.html": f"<html>{body}</html>".encode()},
    )
    text = _booktext.extract(path)
    assert "<p>" not in text
    assert "& more" in text


def test_txtz_joins_every_txt_member(tmp_path: Path) -> None:
    path = make_zip(
        tmp_path / "book.txtz",
        {"b.txt": LONG.encode(), "a.txt": b"first", "img.png": b"x"},
    )
    assert _booktext.extract(path).startswith("first\n\nword")


@pytest.mark.parametrize(
    ("suffix", "members"),
    [(".fbz", {"a.txt": b"x"}), (".htmlz", {"a.png": b"x"}), (".txtz", {})],
)
def test_zip_without_the_text_is_refused(
    tmp_path: Path, suffix: str, members: dict[str, bytes]
) -> None:
    path = make_zip(tmp_path / f"book{suffix}", members)
    with pytest.raises(BookTextError, match=r"has no .* inside"):
        _booktext.extract(path)


def test_zip_that_is_not_a_zip_is_refused(tmp_path: Path) -> None:
    path = tmp_path / "book.txtz"
    path.write_bytes(b"not a zip")
    with pytest.raises(BookTextError, match="not a readable zip"):
        _booktext.extract(path)


def test_zip_bomb_is_refused(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(_booktext, "_MAX_UNZIPPED", 10)
    path = make_zip(tmp_path / "book.txtz", {"a.txt": b"x" * 11})
    with pytest.raises(BookTextError, match="unpacks to more than"):
        _booktext.extract(path)


@pytest.mark.parametrize(
    "suffix",
    [
        ".azw1",
        ".azw4",
        ".prc",
        ".pdb",
        ".lit",
        ".lrf",
        ".rb",
        ".snb",
        ".tcr",
        ".pml",
        ".chm",
        ".cbz",
        ".cbr",
        ".cb7",
        ".cbc",
    ],
)
def test_dropped_formats_are_refused(tmp_path: Path, suffix: str) -> None:
    with pytest.raises(BookTextError, match="not an ebook format"):
        _booktext.extract(tmp_path / f"book{suffix}")
