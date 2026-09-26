# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Any ebook file in, its plain text out.

Three extractors cover every format an ebook realistically comes in:

* ``pdftotext`` (poppler) for PDF -- better paragraph flow than calibre's;
* ``djvutxt`` (djvulibre) for DjVu's hidden text layer;
* calibre's ``ebook-convert`` for everything else it reads: EPUB/KEPUB, MOBI,
  AZW/AZW3/AZW4/KFX-converted, PRC/PDB, FB2/FBZ, LIT, LRF, RB, SNB, TCR, PML,
  CHM, RTF, DOCX, ODT, HTMLZ, TXTZ, comics (CBZ/CBR/CB7/CBC);
* and plain TXT/MD/HTML read directly.

A file that yields almost no text is refused rather than indexed: that is a
scanned PDF without an OCR layer, a comic, or a DRM-locked book, and an empty
index would silently turn every quiz into "the book says nothing".
"""

from __future__ import annotations

import html
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from typing import Final

MIN_BOOK_CHARS: Final = 20_000
"""Well under any real book (a novella is ~150k characters)."""

_CONVERT_TIMEOUT: Final = 600

CALIBRE_SUFFIXES: Final = frozenset(
    {
        ".epub",
        ".kepub",
        ".mobi",
        ".azw",
        ".azw1",
        ".azw3",
        ".azw4",
        ".prc",
        ".pdb",
        ".fb2",
        ".fbz",
        ".lit",
        ".lrf",
        ".rb",
        ".snb",
        ".tcr",
        ".pml",
        ".chm",
        ".rtf",
        ".docx",
        ".odt",
        ".htmlz",
        ".txtz",
        ".cbz",
        ".cbr",
        ".cb7",
        ".cbc",
    }
)
PLAIN_SUFFIXES: Final = frozenset({".txt", ".md", ".text"})
HTML_SUFFIXES: Final = frozenset({".html", ".htm", ".xhtml"})
SUPPORTED: Final = (
    CALIBRE_SUFFIXES
    | PLAIN_SUFFIXES
    | HTML_SUFFIXES
    | frozenset({".pdf", ".djvu", ".djv"})
)

_TAG: Final = re.compile(r"<[^>]+>")
_BLANKS: Final = re.compile(r"[ \t\r\f\v]+")
_PARAS: Final = re.compile(r"\n\s*\n+")


class BookTextError(ValueError):
    """The file could not be turned into usable text; ``str()`` says why."""


def _run(command: list[str]) -> str:
    """Run a converter, returning stdout; raise a readable error on failure."""
    tool = shutil.which(command[0])
    if tool is None:
        msg = f"{command[0]} is not installed (install.sh installs it)"
        raise BookTextError(msg)
    try:
        done = subprocess.run(
            [tool, *command[1:]],
            capture_output=True,
            text=True,
            timeout=_CONVERT_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        msg = f"{command[0]} took longer than {_CONVERT_TIMEOUT}s"
        raise BookTextError(msg) from exc
    if done.returncode != 0:
        tail = (done.stderr or done.stdout).strip().splitlines()[-1:] or ["no output"]
        msg = f"{command[0]} failed: {tail[0][:200]} (DRM-protected?)"
        raise BookTextError(msg)
    return done.stdout


def _calibre(path: Path) -> str:
    with tempfile.TemporaryDirectory(prefix="book-guard-") as tmp:
        out = Path(tmp) / "book.txt"
        _run(["ebook-convert", str(path), str(out)])
        return out.read_text(encoding="utf-8", errors="replace")


def normalise(text: str) -> str:
    """Collapse runs of spaces; keep paragraph breaks as blank lines."""
    paragraphs = (_BLANKS.sub(" ", p).strip() for p in _PARAS.split(text))
    return "\n\n".join(" ".join(p.split("\n")).strip() for p in paragraphs if p.strip())


def extract(path: Path) -> str:
    """The book's text, normalised.

    Raises:
        BookTextError: Unsupported format, converter failure, or too little
            text to be a real book.
    """
    suffix = path.suffix.lower()
    if suffix not in SUPPORTED:
        msg = f"{suffix or 'no extension'} is not an ebook format book-guard reads"
        raise BookTextError(msg)
    if suffix == ".pdf":
        raw = _run(["pdftotext", "-enc", "UTF-8", str(path), "-"])
    elif suffix in {".djvu", ".djv"}:
        raw = _run(["djvutxt", str(path)])
    elif suffix in PLAIN_SUFFIXES:
        raw = path.read_text(encoding="utf-8", errors="replace")
    elif suffix in HTML_SUFFIXES:
        raw = html.unescape(
            _TAG.sub("\n", path.read_text(encoding="utf-8", errors="replace"))
        )
    else:
        raw = _calibre(path)
    text = normalise(raw)
    if len(text) < MIN_BOOK_CHARS:
        msg = (
            f"only {len(text)} characters of text came out -- a scanned PDF "
            "without OCR, a comic, or a DRM-protected file cannot be checked against"
        )
        raise BookTextError(msg)
    return text
