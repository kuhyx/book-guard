# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""book-guard's extractors against calibre's text, one fixture per format.

calibre is only the REFERENCE here (and, for mobi/azw3, the fixture
generator): the product never calls it. The whole module skips when
``ebook-convert`` or ``pandoc`` is missing, so a machine without calibre
still runs the suite. Everything is built in ``tmp_path``; calibre gets a
throw-away HOME (see ``scripts/compare_with_calibre.py``).
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

import pytest

from book_guard import _booktext
from scripts import compare_with_calibre as cmp

_REAL_WHICH = shutil.which
pytestmark = pytest.mark.skipif(
    _REAL_WHICH("ebook-convert") is None or _REAL_WHICH("pandoc") is None,
    reason="needs ebook-convert (reference only) and pandoc",
)

_VOCAB = [
    "ogień",
    "woda",
    "ziemia",
    "powietrze",
    "księga",
    "strona",
    "rozdział",
    "światło",
    "cień",
    "droga",
    "river",
    "mountain",
    "winter",
    "letter",
    "window",
    "garden",
    "silence",
    "morning",
    "engine",
    "zażółć",
    "gęślą",
    "jaźń",
    "chleb",
    "miasto",
    "noc",
    "dzień",
    "pamięć",
    "imię",
]


class _Rng:
    """A tiny deterministic generator, so the fixture text never changes."""

    def __init__(self) -> None:
        self.state = 7

    def randint(self, low: int, high: int) -> int:
        self.state = (self.state * 1103515245 + 12345) % 2**31
        return low + self.state // 7 % (high - low + 1)

    def choice(self, items: list[str]) -> str:
        return items[self.randint(0, len(items) - 1)]


def _markdown() -> str:
    """About 30 000 characters of varied prose, headings, lists and quotes."""
    rng = _Rng()
    parts = ["% Fixture Book\n"]
    for chapter in range(1, 13):
        parts.append(f"# Chapter {chapter}\n")
        for _ in range(6):
            words = [rng.choice(_VOCAB) for _ in range(rng.randint(25, 60))]
            words[3] = f"*{words[3]}*"
            words[9] = f"**{words[9]}**"
            parts.append(" ".join(words).capitalize() + ".\n")
        parts.append("- " + "\n- ".join(rng.choice(_VOCAB) for _ in range(3)) + "\n")
        parts.append("> " + " ".join(rng.choice(_VOCAB) for _ in range(12)) + "\n")
    return "\n".join(parts)


def _pandoc(source: Path, target: Path) -> Path:
    subprocess.run(
        [_REAL_WHICH("pandoc") or "", "-s", "-o", str(target), str(source)],
        check=True,
        capture_output=True,
    )
    return target


def _zip(path: Path, members: dict[str, bytes]) -> Path:
    with zipfile.ZipFile(path, "w") as archive:
        for name, data in members.items():
            archive.writestr(name, data)
    return path


def _calibre_made(epub: Path, target: Path) -> Path:
    """mobi / azw3 fixtures: calibre converts the epub (generator only)."""
    home = target.parent / "calibre-home"
    env = {**os.environ, "HOME": str(home), "QT_QPA_PLATFORM": "offscreen"}
    subprocess.run(
        [_REAL_WHICH("ebook-convert") or "", str(epub), str(target)],
        check=True,
        capture_output=True,
        env=env,
    )
    return target


@pytest.fixture(scope="module")
def books(tmp_path_factory: pytest.TempPathFactory) -> dict[str, Path]:
    """One fixture per kept format, built once per run."""
    root = tmp_path_factory.mktemp("books")
    md = root / "book.md"
    md.write_text(_markdown(), encoding="utf-8")
    made = {
        suffix: _pandoc(md, root / f"book{suffix}")
        for suffix in (".epub", ".fb2", ".docx", ".odt", ".rtf")
    }
    made[".kepub"] = Path(shutil.copy(made[".epub"], root / "book.kepub"))
    made[".fbz"] = _zip(root / "book.fbz", {"book.fb2": made[".fb2"].read_bytes()})
    html = _pandoc(md, root / "index.html")
    made[".htmlz"] = _zip(root / "book.htmlz", {"index.html": html.read_bytes()})
    plain = _pandoc(md, root / "index.txt")
    made[".txtz"] = _zip(root / "book.txtz", {"index.txt": plain.read_bytes()})
    with ThreadPoolExecutor(max_workers=2) as pool:
        mobi = pool.submit(_calibre_made, made[".epub"], root / "book.mobi")
        azw3 = pool.submit(_calibre_made, made[".epub"], root / "book.azw3")
        made[".mobi"], made[".azw3"] = mobi.result(), azw3.result()
    made[".azw"] = Path(shutil.copy(made[".mobi"], root / "book.azw"))
    return made


@pytest.fixture(scope="module")
def references(books: dict[str, Path]) -> dict[str, str]:
    """calibre's text for every fixture, converted in parallel (the slow part)."""
    with ThreadPoolExecutor(max_workers=6) as pool:
        texts = pool.map(cmp.calibre_text, books.values())
        return dict(zip(books, texts, strict=True))


@pytest.fixture(autouse=True)
def _real_tools(
    monkeypatch: pytest.MonkeyPatch,
    run_script: object,
) -> None:
    """The hermetic conftest hides tools; this module needs the real two."""
    monkeypatch.setattr(shutil, "which", _REAL_WHICH)
    monkeypatch.setattr(subprocess, "run", run_script)


@pytest.mark.parametrize(
    "suffix",
    [
        ".epub",
        ".kepub",
        ".fb2",
        ".fbz",
        ".docx",
        ".odt",
        ".rtf",
        ".htmlz",
        ".txtz",
        ".mobi",
        ".azw",
        ".azw3",
    ],
)
def test_text_matches_calibre(
    books: dict[str, Path], references: dict[str, str], suffix: str
) -> None:
    ours = cmp.words(_booktext.extract(books[suffix]))
    theirs = cmp.words(references[suffix])
    assert len(ours) > 3000
    assert cmp.bag_similarity(ours, theirs) >= cmp.THRESHOLD
    assert cmp.ordered_similarity(ours, theirs) >= cmp.THRESHOLD


def test_compare_prints_the_scores(
    books: dict[str, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    assert cmp.main([str(books[".epub"])]) == 0
    assert "ordered=" in capsys.readouterr().out
    assert cmp.main([]) == 1
