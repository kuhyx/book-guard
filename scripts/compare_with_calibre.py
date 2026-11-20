# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Differential check: book-guard's own extractors against calibre's text.

calibre (``ebook-convert``) is NOT part of the product any more; it only
serves here as the reference the pandoc / ``mobi`` extractors are compared
with. The product never calls it.

Similarity is measured two ways on normalised word sequences (lower case,
letters and digits only, so markup and punctuation drop out):

* ``ordered``: ``difflib.SequenceMatcher`` ratio of word 4-grams, order
  sensitive;
* ``bag``: shared words (multiset) over the longer text, order blind, fast
  enough for a whole novel.

``python -m scripts.compare_with_calibre BOOK...`` prints both for each file
(a real book is read in place, nothing is written next to it).
"""

from __future__ import annotations

from collections import Counter
import difflib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Final

from book_guard import _booktext

THRESHOLD: Final = 0.95
"""The agreed floor for both measures."""

_WORD: Final = re.compile(r"\w+")
_TIMEOUT: Final = 600
_SHINGLE: Final = 4


def words(text: str) -> list[str]:
    """Lower-case alphanumeric words, in order."""
    return _WORD.findall(text.lower())


def bag_similarity(left: list[str], right: list[str]) -> float:
    """Shared words over the longer text's word count (order blind)."""
    if not left and not right:
        return 1.0
    shared = sum((Counter(left) & Counter(right)).values())
    return shared / max(len(left), len(right))


def _shingles(tokens: list[str]) -> list[str]:
    return [
        " ".join(tokens[i : i + _SHINGLE]) for i in range(len(tokens) - _SHINGLE + 1)
    ]


def ordered_similarity(left: list[str], right: list[str]) -> float:
    """``SequenceMatcher`` ratio of the two texts' word 4-grams.

    Rare tokens keep the exact matcher fast (single words are so common that
    it takes minutes on a novel) and make a swapped or lost passage count for
    several grams, so this is the stricter of the two measures.
    """
    if len(left) < _SHINGLE or len(right) < _SHINGLE:
        return float(left == right)
    matcher = difflib.SequenceMatcher(
        None, _shingles(left), _shingles(right), autojunk=False
    )
    return matcher.ratio()


def calibre_text(path: Path) -> str:
    """What ``ebook-convert`` makes of ``path``, with a throw-away HOME."""
    with tempfile.TemporaryDirectory(prefix="calibre-ref-") as tmp:
        home = Path(tmp)
        env = {
            **os.environ,
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / "config"),
            "XDG_CACHE_HOME": str(home / "cache"),
            "CALIBRE_CONFIG_DIRECTORY": str(home / "calibre-config"),
            "CALIBRE_CACHE_DIRECTORY": str(home / "calibre-cache"),
            "QT_QPA_PLATFORM": "offscreen",
        }
        out = home / "reference.txt"
        tool = shutil.which("ebook-convert")
        if tool is None:
            msg = "ebook-convert is not installed"
            raise FileNotFoundError(msg)
        subprocess.run(
            [tool, str(path), str(out)],
            check=True,
            capture_output=True,
            env=env,
            timeout=_TIMEOUT,
        )
        return out.read_text(encoding="utf-8", errors="replace")


def compare(path: Path) -> tuple[float, float]:
    """``(ordered, bag)`` similarity of book-guard's text vs calibre's."""
    ours = words(_booktext.extract(path))
    theirs = words(calibre_text(path))
    return ordered_similarity(ours, theirs), bag_similarity(ours, theirs)


def main(argv: list[str]) -> int:
    """Print the two scores per file; exit 1 when any is under the floor."""
    worst = 1.0
    for name in argv:
        ordered, bag = compare(Path(name))
        worst = min(worst, ordered, bag)
        sys.stdout.write(f"{name}: ordered={ordered:.4f} bag={bag:.4f}\n")
    return 0 if argv and worst >= THRESHOLD else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
