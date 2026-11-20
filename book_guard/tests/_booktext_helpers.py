# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Shared by the ``_booktext`` tests: a recording stand-in for ``_run``."""

from __future__ import annotations

from pathlib import Path
import zipfile

from book_guard._booktext import MIN_BOOK_CHARS

LONG = ("word " * (MIN_BOOK_CHARS // 4)).strip()
FIXTURES = Path(__file__).parent / "fixtures"


class FakeRun:
    """Stands in for ``_booktext._run``: records commands, returns text."""

    def __init__(self, stdout: str = LONG) -> None:
        self.stdout = stdout
        self.commands: list[list[str]] = []

    def __call__(self, command: list[str]) -> str:
        self.commands.append(command)
        return self.stdout


def make_zip(path: Path, members: dict[str, bytes]) -> Path:
    """Write a zip with ``members`` (name -> bytes) and return it."""
    with zipfile.ZipFile(path, "w") as archive:
        for name, data in members.items():
            archive.writestr(name, data)
    return path
