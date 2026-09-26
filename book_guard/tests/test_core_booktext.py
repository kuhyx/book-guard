# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_booktext: every format branch, converter failures, too-short text."""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess

import pytest

from book_guard import _booktext
from book_guard._booktext import MIN_BOOK_CHARS, BookTextError

_LONG = ("word " * (MIN_BOOK_CHARS // 4)).strip()


class FakeRun:
    """Stands in for ``_booktext._run``: records commands, returns text."""

    def __init__(self, stdout: str = _LONG) -> None:
        self.stdout = stdout
        self.commands: list[list[str]] = []

    def __call__(self, command: list[str]) -> str:
        self.commands.append(command)
        if command[0] == "ebook-convert":
            Path(command[2]).write_text(self.stdout, encoding="utf-8")
            return ""
        return self.stdout


@pytest.fixture
def fake_run(monkeypatch: pytest.MonkeyPatch) -> FakeRun:
    fake = FakeRun()
    monkeypatch.setattr(_booktext, "_run", fake)
    return fake


def test_normalise() -> None:
    raw = "  one\t\ftwo\nthree\n\n\n  \nfour\nfive\n\n"
    assert _booktext.normalise(raw) == "one two three\n\nfour five"


@pytest.mark.parametrize("name", ["book.exe", "README"])
def test_unsupported_suffix(tmp_path: Path, name: str) -> None:
    with pytest.raises(BookTextError, match="not an ebook format"):
        _booktext.extract(tmp_path / name)


def test_no_extension_message(tmp_path: Path) -> None:
    with pytest.raises(BookTextError, match="no extension"):
        _booktext.extract(tmp_path / "README")


def test_plain_text(tmp_path: Path) -> None:
    path = tmp_path / "book.TXT"
    path.write_text(_LONG, encoding="utf-8")
    assert _booktext.extract(path) == _LONG


def test_html(tmp_path: Path) -> None:
    path = tmp_path / "book.xhtml"
    body = "".join(f"<p>{_LONG[:500]} &amp; more</p>" for _ in range(50))
    path.write_text(f"<html><body>{body}</body></html>", encoding="utf-8")
    text = _booktext.extract(path)
    assert "<p>" not in text
    assert "& more" in text


def test_pdf(tmp_path: Path, fake_run: FakeRun) -> None:
    path = tmp_path / "book.pdf"
    assert _booktext.extract(path) == _LONG
    assert fake_run.commands == [["pdftotext", "-enc", "UTF-8", str(path), "-"]]


@pytest.mark.parametrize("suffix", [".djvu", ".djv"])
def test_djvu(tmp_path: Path, fake_run: FakeRun, suffix: str) -> None:
    path = tmp_path / f"book{suffix}"
    assert _booktext.extract(path) == _LONG
    assert fake_run.commands == [["djvutxt", str(path)]]


def test_calibre(tmp_path: Path, fake_run: FakeRun) -> None:
    path = tmp_path / "book.epub"
    assert _booktext.extract(path) == _LONG
    command = fake_run.commands[0]
    assert command[:2] == ["ebook-convert", str(path)]
    assert command[2].endswith("book.txt")
    assert not Path(command[2]).exists()  # temp dir cleaned up


def test_too_short_is_refused(tmp_path: Path, fake_run: FakeRun) -> None:
    fake_run.stdout = "a scanned pdf"
    with pytest.raises(BookTextError, match="only 13 characters"):
        _booktext.extract(tmp_path / "scan.pdf")


def test_run_missing_tool() -> None:
    # conftest makes shutil.which find nothing.
    with pytest.raises(BookTextError, match="pdftotext is not installed"):
        _booktext._run(["pdftotext", "x"])


class FakeSubprocess:
    def __init__(self, result: subprocess.CompletedProcess[str] | Exception) -> None:
        self.result = result
        self.calls: list[tuple[list[str], dict[str, object]]] = []

    def __call__(
        self, command: list[str], **kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        self.calls.append((command, kwargs))
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


def _with_tool(
    monkeypatch: pytest.MonkeyPatch,
    result: subprocess.CompletedProcess[str] | Exception,
) -> FakeSubprocess:
    fake = FakeSubprocess(result)
    monkeypatch.setattr(shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(subprocess, "run", fake)
    return fake


def test_run_success(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = _with_tool(monkeypatch, subprocess.CompletedProcess([], 0, "out", ""))
    assert _booktext._run(["djvutxt", "f.djvu"]) == "out"
    command, kwargs = fake.calls[0]
    assert command == ["/usr/bin/djvutxt", "f.djvu"]
    assert kwargs["timeout"] == 600
    assert kwargs["check"] is False


@pytest.mark.parametrize(
    ("stdout", "stderr", "tail"),
    [
        ("", "warn\nDRM detected\n", "DRM detected"),
        ("stdout line\n", "", "stdout line"),
        ("", "", "no output"),
    ],
)
def test_run_failure(
    monkeypatch: pytest.MonkeyPatch, stdout: str, stderr: str, tail: str
) -> None:
    _with_tool(monkeypatch, subprocess.CompletedProcess([], 1, stdout, stderr))
    with pytest.raises(BookTextError, match=f"ebook-convert failed: {tail}"):
        _booktext._run(["ebook-convert", "a", "b"])


def test_run_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    _with_tool(monkeypatch, subprocess.TimeoutExpired("pdftotext", 600))
    with pytest.raises(BookTextError, match="longer than 600s"):
        _booktext._run(["pdftotext", "x"])
