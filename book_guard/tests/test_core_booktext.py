# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_booktext: every format branch, converter failures, too-short text."""

from __future__ import annotations

import shutil
import subprocess
from typing import TYPE_CHECKING

import pytest

from book_guard import _booktext
from book_guard._booktext import BookTextError
from book_guard.tests import _booktext_helpers as helpers
from book_guard.tests._booktext_helpers import LONG

if TYPE_CHECKING:
    from pathlib import Path


@pytest.fixture
def fake_run(monkeypatch: pytest.MonkeyPatch) -> helpers.FakeRun:
    fake = helpers.FakeRun()
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
    path.write_text(LONG, encoding="utf-8")
    assert _booktext.extract(path) == LONG


def test_html(tmp_path: Path) -> None:
    path = tmp_path / "book.xhtml"
    body = "".join(f"<p>{LONG[:500]} &amp; more</p>" for _ in range(50))
    head = "<head><STYLE>p {color: red}</STYLE><script>var hidden = 1;</script></head>"
    path.write_text(f"<html>{head}<body>{body}</body></html>", encoding="utf-8")
    text = _booktext.extract(path)
    assert "color: red" not in text
    assert "hidden" not in text
    assert "<p>" not in text
    assert "& more" in text


def test_pdf(tmp_path: Path, fake_run: helpers.FakeRun) -> None:
    path = tmp_path / "book.pdf"
    assert _booktext.extract(path) == LONG
    assert fake_run.commands == [["pdftotext", "-enc", "UTF-8", str(path), "-"]]


@pytest.mark.parametrize("suffix", [".djvu", ".djv"])
def test_djvu(tmp_path: Path, fake_run: helpers.FakeRun, suffix: str) -> None:
    path = tmp_path / f"book{suffix}"
    assert _booktext.extract(path) == LONG
    assert fake_run.commands == [["djvutxt", str(path)]]


_PANDOC_FORMATS = {
    ".epub": "epub",
    ".kepub": "epub",
    ".fb2": "fb2",
    ".docx": "docx",
    ".odt": "odt",
    ".rtf": "rtf",
}


@pytest.mark.parametrize(("suffix", "reader"), _PANDOC_FORMATS.items())
def test_pandoc(
    tmp_path: Path, fake_run: helpers.FakeRun, suffix: str, reader: str
) -> None:
    path = tmp_path / f"book{suffix.upper()}"
    assert _booktext.extract(path) == LONG
    assert fake_run.commands == [
        ["pandoc", "--sandbox", "-f", reader, "-t", "plain", "--wrap=none", str(path)]
    ]


def test_too_short_is_refused(tmp_path: Path, fake_run: helpers.FakeRun) -> None:
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
    with pytest.raises(BookTextError, match=f"pandoc failed: {tail}"):
        _booktext._run(["pandoc", "a", "b"])


def test_run_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    _with_tool(monkeypatch, subprocess.TimeoutExpired("pdftotext", 600))
    with pytest.raises(BookTextError, match="longer than 600s"):
        _booktext._run(["pdftotext", "x"])
