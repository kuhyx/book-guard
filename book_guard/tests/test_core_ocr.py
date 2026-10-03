# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_ocr: local tools faked at the subprocess boundary."""

from __future__ import annotations

import io
import subprocess
from typing import TYPE_CHECKING

from PIL import Image
import pytest

from book_guard import _ocr
from book_guard._ocr import Word

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

_HEADER = "level\tpage\tblock\tpar\tline\tword\tleft\ttop\twidth\theight\tconf\ttext"


def tsv(*rows: tuple[str, int, int, int, int, float, str]) -> str:
    """Tesseract TSV: (line, left, top, width, height, conf, text) per word."""
    body = [
        f"5\t1\t1\t1\t{line}\t1\t{left}\t{top}\t{width}\t{height}\t{conf}\t{text}"
        for line, left, top, width, height, conf, text in rows
    ]
    return "\n".join([_HEADER, *body]) + "\n"


def _tools(
    monkeypatch: pytest.MonkeyPatch,
    answer: dict[str, Callable[[list[str], bytes], str] | Exception],
) -> list[list[str]]:
    """``shutil.which`` finds the named tools; ``subprocess.run`` answers."""
    calls: list[list[str]] = []
    monkeypatch.setattr(
        "book_guard._ocr.shutil.which",
        lambda name: f"/usr/bin/{name}" if name in answer else None,
    )

    def run(argv: list[str], **kwargs: object) -> subprocess.CompletedProcess[bytes]:
        calls.append(argv)
        stdin = kwargs.get("input", b"")
        assert isinstance(stdin, bytes)
        out = answer[argv[0].rsplit("/", 1)[-1]]
        if isinstance(out, Exception):
            raise out
        return subprocess.CompletedProcess(argv, 0, stdout=out(argv, stdin).encode())

    monkeypatch.setattr("book_guard._ocr.subprocess.run", run)
    return calls


def _jpeg(tmp_path: Path, size: tuple[int, int] = (80, 60)) -> Path:
    path = tmp_path / "p.jpg"
    Image.new("RGB", size, "white").save(path)
    return path


def _osd(rotate: int, conf: float) -> Callable[[list[str], bytes], str]:
    """OSD answers ``rotate``/``conf``; every TSV call gets two lines."""

    def answer(argv: list[str], _png: bytes) -> str:
        if "0" in argv and "--psm" in argv and argv[argv.index("--psm") + 1] == "0":
            return f"Rotate: {rotate}\nOrientation confidence: {conf}\n"
        return tsv(
            ("1", 5, 5, 40, 10, 95.0, "Komu-"),
            ("2", 5, 20, 40, 10, 95.0, "nistyczna"),
            ("3", 30, 50, 6, 8, 96.0, "51"),
        )

    return answer


def test_no_tools_means_no_local_reading(tmp_path: Path) -> None:
    assert _ocr.barcode_isbn(_jpeg(tmp_path)) is None
    assert _ocr.scan(_jpeg(tmp_path)) is None
    assert _ocr.tesseract(Image.new("L", (4, 4))) == ""


def test_barcode(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    calls = _tools(
        monkeypatch,
        {"zbarimg": lambda _a, _i: "5901234123457\n978-83-6838-000-2\n"},
    )
    assert _ocr.barcode_isbn(_jpeg(tmp_path)) == "9788368380002"
    assert "-Sean13.enable" in calls[0]
    _tools(monkeypatch, {"zbarimg": lambda _a, _i: "5901234123457\n"})
    assert _ocr.barcode_isbn(_jpeg(tmp_path)) is None


@pytest.mark.parametrize("error", [OSError("gone"), subprocess.TimeoutExpired("t", 1)])
def test_tool_failure_is_no_reading(
    monkeypatch: pytest.MonkeyPatch, error: Exception
) -> None:
    _tools(monkeypatch, {"tesseract": error})
    gray = Image.new("L", (40, 40), 255)
    assert _ocr.tesseract(gray, "--psm", "0") == ""
    assert _ocr.upright(gray) == (gray, 0)


def test_words_skip_what_is_not_a_word() -> None:
    raw = tsv(("1", 1, 2, 3, 4, 90.0, "ok"), ("1", 1, 2, 3, 4, 90.0, " "))
    raw += "5\t1\t1\t1\t1\t1\tx\t2\t3\t4\t90\tbad\n"  # non-numeric box
    raw += "short\trow\n"
    assert _ocr.words(raw) == [
        Word(text="ok", conf=90.0, box=(1, 2, 4, 6), line=("1", "1", "1"))
    ]


def test_confident_osd_turns_the_page(monkeypatch: pytest.MonkeyPatch) -> None:
    calls = _tools(monkeypatch, {"tesseract": _osd(90, 16.3)})
    turned, angle = _ocr.upright(Image.new("L", (80, 60), 255))
    assert (angle, turned.size) == (270, (60, 80))
    assert len(calls) == 1  # no rotation scoring needed


def test_unsure_osd_scores_all_four_turns(monkeypatch: pytest.MonkeyPatch) -> None:
    """Only the turn that brings the ink dot to the top-left reads as text."""

    def answer(argv: list[str], png: bytes) -> str:
        if argv[argv.index("--psm") + 1] == "0":
            return "garbage"
        image = Image.open(io.BytesIO(png))
        pixel = image.getpixel((0, 0))
        assert isinstance(pixel, (int, float))
        if pixel < 128:
            return tsv(*[("1", 0, 0, 30, 10, 95.0, "słowo")] * 5)
        return tsv(("1", 0, 0, 10, 30, 95.0, "pionowe"))  # tall: sideways

    _tools(monkeypatch, {"tesseract": answer})
    gray = Image.new("L", (60, 60), 255)
    gray.putpixel((59, 59), 0)
    _turned, angle = _ocr.upright(gray)
    assert angle == 180


def test_scan_reads_words_text_and_keeps_the_page(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _tools(monkeypatch, {"tesseract": _osd(0, 9.0)})
    page = _ocr.scan(_jpeg(tmp_path))
    assert page is not None
    assert (page.rotation, page.size, page.image.size) == (0, (80, 60), (80, 60))
    assert page.text == "Komunistyczna\n51"
    assert [w.text for w in page.words] == ["Komu-", "nistyczna", "51"]


def test_text_is_capped() -> None:
    long = [
        _ocr.Word("x" * 100, 90.0, (0, 0, 1, 1), (str(i), "1", "1")) for i in range(30)
    ]
    assert len(_ocr.page_text(long)) == _ocr.TEXT_LIMIT


def test_unreadable_image(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _tools(monkeypatch, {"tesseract": _osd(0, 9.0)})
    bad = tmp_path / "bad.jpg"
    bad.write_bytes(b"not an image")
    assert _ocr.open_gray(bad) is None
    assert _ocr.scan(bad) is None


def test_flatten_turns_shadow_white() -> None:
    gray = Image.new("L", (200, 200), 90)  # an evenly dark page
    gray.putpixel((100, 100), 10)  # one ink dot
    flat = _ocr.flatten(gray)
    assert flat.getpixel((5, 5)) == 255
    assert flat.getpixel((100, 100)) != 255
