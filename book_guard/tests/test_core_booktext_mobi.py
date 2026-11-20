# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_booktext: MOBI / AZW / AZW3 through the ``mobi`` package."""

from __future__ import annotations

from pathlib import Path
import shutil
import tempfile

import mobi
import pytest

from book_guard import _booktext
from book_guard._booktext import BookTextError
from book_guard.tests import _booktext_helpers as helpers
from book_guard.tests._booktext_helpers import LONG


@pytest.fixture
def fake_run(monkeypatch: pytest.MonkeyPatch) -> helpers.FakeRun:
    fake = helpers.FakeRun()
    monkeypatch.setattr(_booktext, "_run", fake)
    return fake


@pytest.fixture
def small_book(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> Path:
    """Tiny fixture books are far under the real minimum; scratch in tmp."""
    monkeypatch.setattr(_booktext, "MIN_BOOK_CHARS", 100)
    scratch = tmp_path / "scratch"
    scratch.mkdir()
    monkeypatch.setattr(tempfile, "tempdir", str(scratch))
    return scratch


@pytest.mark.parametrize("suffix", [".mobi", ".azw"])
def test_mobi7_goes_through_the_html_path(
    small_book: Path, tmp_path: Path, suffix: str
) -> None:
    path = tmp_path / f"book{suffix}"
    shutil.copy(helpers.FIXTURES / "tiny.mobi", path)
    text = _booktext.extract(path)
    assert "The quick brown fox number 3 jumps over the lazy dog" in text
    assert "zażółć gęślą jaźń" in text
    assert "<p" not in text
    assert not list(small_book.iterdir())  # nothing left behind


def test_azw3_goes_through_pandoc(
    small_book: Path, tmp_path: Path, fake_run: helpers.FakeRun
) -> None:
    path = tmp_path / "book.azw3"
    shutil.copy(helpers.FIXTURES / "tiny.azw3", path)
    fake_run.stdout = LONG
    assert _booktext.extract(path) == LONG
    command = fake_run.commands[0]
    assert command[:7] == [
        "pandoc",
        "--sandbox",
        "-f",
        "epub",
        "-t",
        "plain",
        "--wrap=none",
    ]
    assert command[7].endswith(".epub")
    assert not list(small_book.iterdir())


def test_mobi_pdf_replica_goes_through_pdftotext(
    small_book: Path,
    tmp_path: Path,
    fake_run: helpers.FakeRun,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fake_extract(_path: str) -> tuple[str, str]:
        folder = tempfile.mkdtemp(prefix="mobiex")
        (Path(folder) / "book.001.pdf").write_bytes(b"%PDF")
        return folder, str(Path(folder) / "book.001.pdf")

    monkeypatch.setattr(mobi, "extract", fake_extract)
    assert _booktext.extract(tmp_path / "book.mobi") == LONG
    assert fake_run.commands[0][:3] == ["pdftotext", "-enc", "UTF-8"]
    assert not list(small_book.iterdir())


def test_mobi_unknown_output_is_refused(
    small_book: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    def fake_extract(_path: str) -> tuple[str, str]:
        folder = tempfile.mkdtemp(prefix="mobiex")
        return folder, str(Path(folder) / "weird.bin")

    monkeypatch.setattr(mobi, "extract", fake_extract)
    with pytest.raises(BookTextError, match=r"unexpected \.bin"):
        _booktext.extract(tmp_path / "book.mobi")
    assert not list(small_book.iterdir())


def test_mobi_failure_fails_closed(
    small_book: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    def fail(_path: str) -> tuple[str, str]:
        tempfile.mkdtemp(prefix="mobiex")  # what a half-done unpack leaves
        msg = "DRM protected"
        raise ValueError(msg)

    monkeypatch.setattr(mobi, "extract", fail)
    with pytest.raises(BookTextError, match="mobi failed: DRM protected"):
        _booktext.extract(tmp_path / "book.mobi")
    assert not list(small_book.iterdir())


def test_mobi_garbage_file_fails_closed(small_book: Path, tmp_path: Path) -> None:
    path = tmp_path / "book.mobi"
    path.write_bytes(b"not a mobi at all" * 100)
    with pytest.raises(BookTextError, match="mobi failed"):
        _booktext.extract(path)
    assert not list(small_book.iterdir())
