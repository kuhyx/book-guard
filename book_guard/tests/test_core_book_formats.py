# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The app's attach modal lists exactly the formats the PC reads.

Dart cannot import Python, so this parses ``app/lib/src/book_formats.dart``
(one ``BookFormatGroup('<key>', '<label>', [...])`` per group, plain string
literals) and compares it with :data:`book_guard._booktext.FORMAT_GROUPS`.
"""

from __future__ import annotations

from pathlib import Path
import re

from book_guard._booktext import FORMAT_GROUPS, SUPPORTED

DART = Path(__file__).resolve().parents[2] / "app/lib/src/book_formats.dart"
_GROUP = re.compile(
    r"BookFormatGroup\(\s*'(\w+)',\s*'[^']*',\s*\[(.*?)\]\s*,?\s*\)", re.DOTALL
)
_EXT = re.compile(r"'([a-z0-9]+)'")


def _dart_groups() -> dict[str, list[str]]:
    source = DART.read_text(encoding="utf-8")
    body = source[source.index("const bookFormatGroups") :]
    return {key: _EXT.findall(items) for key, items in _GROUP.findall(body)}


def test_dart_groups_match_python() -> None:
    dart = _dart_groups()
    assert list(dart) == list(FORMAT_GROUPS)
    for key, suffixes in FORMAT_GROUPS.items():
        assert sorted(f".{e}" for e in dart[key]) == sorted(suffixes), key


def test_no_extension_is_listed_twice() -> None:
    flat = [e for exts in _dart_groups().values() for e in exts]
    assert len(flat) == len(set(flat)) == len(SUPPORTED)
