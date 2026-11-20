# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Any ebook file in, its plain text out.

Four extractors cover every format an ebook realistically comes in:

* ``pdftotext`` (poppler) for PDF -- better paragraph flow than a converter's;
* ``djvutxt`` (djvulibre) for DjVu's hidden text layer;
* ``pandoc`` for EPUB/KEPUB, FB2, DOCX, ODT and RTF (and FBZ, a zipped FB2);
* the ``mobi`` package for MOBI/AZW/AZW3: it unpacks the Kindle container to
  an HTML or EPUB file that goes through the HTML / pandoc path;
* ``zipfile`` for HTMLZ and TXTZ (a zip holding one HTML / text file);
* and plain TXT/MD/HTML read directly.

Until 2026-11-20 everything beyond PDF/DjVu went through calibre's
``ebook-convert``; it was dropped (calibre pulls in a non-free unrar), and
the rarely used formats only it read (AZW1/4, PRC, PDB, LIT, LRF, RB, SNB,
TCR, PML, CHM and the CBZ/CBR/CB7/CBC comics) went with it.

A file that yields almost no text is refused rather than indexed: that is a
scanned PDF without an OCR layer, a comic, or a DRM-locked book, and an empty
index would silently turn every quiz into "the book says nothing". Every
converter failure raises :class:`BookTextError` too (fail closed): the book
is never half-indexed.
"""

from __future__ import annotations

import contextlib
import html
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from typing import TYPE_CHECKING, Final
import zipfile

from loguru import logger
import mobi

if TYPE_CHECKING:
    from collections.abc import Iterator

MIN_BOOK_CHARS: Final = 20_000
"""Well under any real book (a novella is ~150k characters)."""

_CONVERT_TIMEOUT: Final = 600
_MAX_UNZIPPED: Final = 1 << 29
"""A zipped book unpacking to more than 512 MiB is a bomb, not a book."""

logger.disable("mobi")  # its DEBUG chatter would flood the journal

PANDOC_FORMATS: Final = {
    ".epub": "epub",
    ".kepub": "epub",
    ".fb2": "fb2",
    ".docx": "docx",
    ".odt": "odt",
    ".rtf": "rtf",
}
"""Suffix -> pandoc reader (a Kobo ``.kepub`` is an EPUB)."""
MOBI_SUFFIXES: Final = frozenset({".mobi", ".azw", ".azw3"})
ZIP_SUFFIXES: Final = frozenset({".fbz", ".htmlz", ".txtz"})
EBOOK_SUFFIXES: Final = frozenset(PANDOC_FORMATS) | MOBI_SUFFIXES | ZIP_SUFFIXES
PLAIN_SUFFIXES: Final = frozenset({".txt", ".md", ".text"})
HTML_SUFFIXES: Final = frozenset({".html", ".htm", ".xhtml"})
FORMAT_GROUPS: Final[dict[str, frozenset[str]]] = {
    "ebook": EBOOK_SUFFIXES,
    "pdf": frozenset({".pdf"}),
    "djvu": frozenset({".djvu", ".djv"}),
    "text": PLAIN_SUFFIXES | HTML_SUFFIXES,
}
"""Every readable format, by the tool that reads it. The app's attach modal
lists the same groups (``app/lib/src/book_formats.dart``); a test parses that
file and fails on any drift, so this stays the one source."""
SUPPORTED: Final = frozenset().union(*FORMAT_GROUPS.values())

_CODE: Final = re.compile(r"<(style|script)\b.*?</\1\s*>", re.DOTALL | re.IGNORECASE)
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


def _pandoc(path: Path, reader: str) -> str:
    # --sandbox: an untrusted book may not make pandoc read other files or
    # reach the network.
    return _run(
        ["pandoc", "--sandbox", "-f", reader, "-t", "plain", "--wrap=none", str(path)]
    )


def _html_text(raw: str) -> str:
    """Visible text of HTML: CSS and scripts dropped, tags to line breaks."""
    return html.unescape(_TAG.sub("\n", _CODE.sub("", raw)))


def _zip_members(path: Path, suffixes: tuple[str, ...]) -> list[tuple[str, bytes]]:
    """The members of a zipped book ending in ``suffixes``, by name."""
    try:
        with zipfile.ZipFile(path) as archive:
            infos = sorted(
                (
                    i
                    for i in archive.infolist()
                    if i.filename.lower().endswith(suffixes)
                ),
                key=lambda i: i.filename,
            )
            if sum(i.file_size for i in infos) > _MAX_UNZIPPED:
                msg = f"{path.suffix} unpacks to more than {_MAX_UNZIPPED >> 20} MiB"
                raise BookTextError(msg)
            members = [(i.filename, archive.read(i)) for i in infos]
    except (zipfile.BadZipFile, OSError) as exc:
        msg = f"{path.suffix} is not a readable zip ({exc})"
        raise BookTextError(msg) from exc
    if not members:
        msg = f"{path.suffix} has no {'/'.join(suffixes)} file inside"
        raise BookTextError(msg)
    return members


def _fbz(path: Path) -> str:
    """A zipped FB2: hand the inner file to pandoc."""
    name, data = _zip_members(path, (".fb2",))[0]
    with tempfile.TemporaryDirectory(prefix="book-guard-") as tmp:
        inner = Path(tmp) / Path(name).name
        inner.write_bytes(data)
        return _pandoc(inner, "fb2")


def _zipped_text(path: Path) -> str:
    """HTMLZ (HTML) or TXTZ (text): every matching member, joined."""
    html_book = path.suffix == ".htmlz"
    suffixes = (".html", ".htm", ".xhtml") if html_book else (".txt",)
    parts = [
        data.decode("utf-8", errors="replace")
        for _name, data in _zip_members(path, suffixes)
    ]
    return "\n\n".join(_html_text(p) if html_book else p for p in parts)


@contextlib.contextmanager
def _scratch_tempdir() -> Iterator[Path]:
    """A temp dir that also catches what ``mobi.extract`` makes with mkdtemp.

    ``mobi.extract`` picks its own directory under the default temp root and
    leaves it behind when the unpack fails half-way; pointing the default at
    a directory of ours removes whatever it left.
    """
    with tempfile.TemporaryDirectory(prefix="book-guard-") as tmp:
        saved = tempfile.tempdir
        tempfile.tempdir = tmp
        try:
            yield Path(tmp)
        finally:
            tempfile.tempdir = saved


def _mobi(path: Path) -> str:
    """Unpack a MOBI/AZW/AZW3 and read what comes out (HTML, EPUB or PDF)."""
    with _scratch_tempdir():
        try:
            _folder, unpacked = mobi.extract(str(path))
        except Exception as exc:
            # The unpacker raises anything on a damaged or DRM-locked file;
            # all of them mean the same refusal.
            msg = f"mobi failed: {str(exc)[:200]} (DRM-protected?)"
            raise BookTextError(msg) from exc
        out = Path(unpacked)
        if out.suffix == ".epub":
            return _pandoc(out, "epub")
        if out.suffix == ".pdf":
            return _run(["pdftotext", "-enc", "UTF-8", str(out), "-"])
        if out.suffix == ".html":
            return _html_text(out.read_text(encoding="utf-8", errors="replace"))
        msg = f"mobi made an unexpected {out.suffix} file"
        raise BookTextError(msg)


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
        raw = _html_text(path.read_text(encoding="utf-8", errors="replace"))
    elif suffix in PANDOC_FORMATS:
        raw = _pandoc(path, PANDOC_FORMATS[suffix])
    elif suffix in MOBI_SUFFIXES:
        raw = _mobi(path)
    elif suffix == ".fbz":
        raw = _fbz(path)
    else:
        raw = _zipped_text(path)
    text = normalise(raw)
    if len(text) < MIN_BOOK_CHARS:
        msg = (
            f"only {len(text)} characters of text came out -- a scanned PDF "
            "without OCR, a comic, or a DRM-protected file cannot be checked against"
        )
        raise BookTextError(msg)
    return text
