# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_ocr and _reader: local tools faked at the subprocess boundary."""

from __future__ import annotations

import subprocess
from typing import TYPE_CHECKING

from PIL import Image
import pytest

from book_guard import _ocr, _reader, _vision
from book_guard._vision import ISBN, OTHER, PAGE, Reading

if TYPE_CHECKING:
    from pathlib import Path


def _tools(
    monkeypatch: pytest.MonkeyPatch, outputs: dict[str, bytes | Exception]
) -> list[list[str]]:
    """``shutil.which`` finds the named tools; ``subprocess.run`` answers."""
    calls: list[list[str]] = []
    monkeypatch.setattr(
        "book_guard._ocr.shutil.which",
        lambda name: f"/usr/bin/{name}" if name in outputs else None,
    )

    def run(argv: list[str], **_kwargs: object) -> subprocess.CompletedProcess[bytes]:
        calls.append(argv)
        out = outputs[argv[0].rsplit("/", 1)[-1]]
        if isinstance(out, Exception):
            raise out
        return subprocess.CompletedProcess(argv, 0, stdout=out)

    monkeypatch.setattr("book_guard._ocr.subprocess.run", run)
    return calls


def _jpeg(tmp_path: Path) -> Path:
    path = tmp_path / "p.jpg"
    Image.new("RGB", (80, 60), "white").save(path)
    return path


def test_no_tools_means_no_local_reading(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _tools(monkeypatch, {})
    assert _ocr.barcode_isbn(_jpeg(tmp_path)) is None
    assert _ocr.page_text(_jpeg(tmp_path)) == ""


def test_barcode(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    calls = _tools(monkeypatch, {"zbarimg": b"5901234123457\n978-83-6838-000-2\n"})
    assert _ocr.barcode_isbn(_jpeg(tmp_path)) == "9788368380002"
    assert "-Sean13.enable" in calls[0]
    _tools(monkeypatch, {"zbarimg": b"5901234123457\n"})
    assert _ocr.barcode_isbn(_jpeg(tmp_path)) is None


@pytest.mark.parametrize("error", [OSError("gone"), subprocess.TimeoutExpired("t", 1)])
def test_tool_failure_is_no_reading(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, error: Exception
) -> None:
    _tools(monkeypatch, {"tesseract": error})
    assert _ocr.page_text(_jpeg(tmp_path)) == ""


def test_page_text(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    raw = "Komu-\nnistycznej Partii\n\n\n\nChin" + "x" * 2000
    calls = _tools(monkeypatch, {"tesseract": raw.encode()})
    text = _ocr.page_text(_jpeg(tmp_path))
    assert text.startswith("Komunistycznej Partii\nChin")
    assert len(text) == _ocr.TEXT_LIMIT
    assert calls[0][1:3] == ["stdin", "-"]


def test_unreadable_image(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _tools(monkeypatch, {"tesseract": b"never"})
    bad = tmp_path / "bad.jpg"
    bad.write_bytes(b"not an image")
    assert _ocr.page_text(bad) == ""


def test_flatten_turns_shadow_white() -> None:
    gray = Image.new("L", (200, 200), 90)  # an evenly dark page
    gray.putpixel((100, 100), 10)  # one ink dot
    flat = _ocr.flatten(gray)
    assert flat.getpixel((5, 5)) == 255
    assert flat.getpixel((100, 100)) != 255


def _never(_b64: str) -> Reading:
    raise AssertionError


def test_reader_barcode_needs_no_model(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(_reader, "barcode_isbn", lambda _p: "9788368380002")
    reading = _reader.read(_jpeg(tmp_path), "B64", full=_never, number=_never)
    assert reading == Reading(ISBN, None, "9788368380002", "")


def test_reader_short_text_asks_for_everything(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(_reader, "barcode_isbn", lambda _p: None)
    monkeypatch.setattr(_reader, "page_text", lambda _p: "short")
    full = Reading(PAGE, 7, None, "model text")
    assert (
        _reader.read(_jpeg(tmp_path), "B64", full=lambda _b: full, number=_never)
        == full
    )


@pytest.mark.parametrize(
    ("answer", "text"),
    [(Reading(PAGE, 19, None, ""), "t" * 300), (Reading(OTHER, None, None, ""), "")],
)
def test_reader_local_text_and_model_number(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, answer: Reading, text: str
) -> None:
    monkeypatch.setattr(_reader, "barcode_isbn", lambda _p: None)
    monkeypatch.setattr(_reader, "page_text", lambda _p: "t" * 300)
    reading = _reader.read(
        _jpeg(tmp_path), "B64", full=_never, number=lambda _b: answer
    )
    assert (reading.kind, reading.page_number, reading.text) == (
        answer.kind,
        answer.page_number,
        text,
    )


def test_read_page_number_asks_without_transcription(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    prompts: list[str] = []

    def ask(
        _system: str, prompt: str, images: list[str], *, model: str
    ) -> dict[str, object]:
        prompts.append(prompt)
        assert (images, model) == (["B64"], "haiku")
        return {"kind": "page", "page_number": 19}

    monkeypatch.setattr(_vision, "ask", ask)
    assert _vision.read_page_number("B64").page_number == 19
    assert "---TEXT---" not in prompts[0]
