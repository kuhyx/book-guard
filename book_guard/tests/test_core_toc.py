# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_toc: contents lines -> chapters."""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from book_guard import _toc
from book_guard._books import Chapter

if TYPE_CHECKING:
    import pytest


def test_parse_toc() -> None:
    text = """SPIS TREŚCI
Krótki przewodnik po Chinach ............ 7
Wstęp ................eeeesss 13
1. Książę . . . . . . 25
Rozdział 2 — Wygnanie 51
1949 89
Ab 120
Przypisy 389
"""
    assert _toc.parse_toc(text) == (
        Chapter(7, "Krótki przewodnik po Chinach"),
        Chapter(13, "Wstęp"),
        Chapter(25, "1. Książę"),
        Chapter(51, "Rozdział 2 — Wygnanie"),
        Chapter(389, "Przypisy"),
    )


def test_transcribe_and_read(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        _toc, "ask", lambda *_a, **_k: {"kind": "toc", "text": "Wstęp 13"}
    )
    assert _toc.transcribe("B64") == "Wstęp 13"
    monkeypatch.setattr(_toc, "ask", lambda *_a, **_k: {"kind": "toc"})
    assert _toc.transcribe("B64") == ""
    chapters = _toc.read_toc(Path("x.jpg"), "B64", model_text=lambda _b: "Wstęp 13")
    assert chapters == (Chapter(13, "Wstęp"),)
