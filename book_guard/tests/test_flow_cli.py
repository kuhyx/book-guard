# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Every ``book-guard`` subcommand through ``main([...])``, plus ``-m``."""

from __future__ import annotations

from dataclasses import replace
from datetime import date, datetime
import io
import json
import runpy
import sys
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _cli, _grading
from book_guard._claude import ClaudeUnavailableError
from book_guard._http import UnavailableError
from book_guard._inbox import InboxResult
from book_guard._openlibrary import BookInfo
from book_guard._photos import REJECTED
from book_guard._pictos import BOOK, CAMERA, GLYPH, NO, OK, OVERLAP, WARN
from book_guard._quiz import Verdict
from book_guard._state import snapshot
from book_guard.tests._flow_helpers import (
    ISBN13,
    LONG_TEXT,
    T0,
    add_book,
    quiz_pair,
    rec,
    seed_photos,
)

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths

Out = pytest.CaptureFixture[str]


def _offline(*_args: object, **_kwargs: object) -> Any:
    msg = "no route to host"
    raise OSError(msg)


def test_search(monkeypatch: pytest.MonkeyPatch, capsys: Out) -> None:
    monkeypatch.setattr(_cli, "search_title", _offline)
    assert _cli.main(["search", "war"]) == 1
    assert capsys.readouterr().err == f"{GLYPH[WARN]}\n"

    monkeypatch.setattr(_cli, "search_title", lambda _t: [])
    assert _cli.main(["search", "war"]) == 1
    assert capsys.readouterr().out == f"{GLYPH[NO]}\n"

    hits = [
        BookInfo(title="War", author="Tol", pages=900, isbn=ISBN13),
        BookInfo(title="Peace", author="", pages=None, isbn=None),
    ]
    monkeypatch.setattr(_cli, "search_title", lambda _t: hits)
    assert _cli.main(["search", "war"]) == 0
    out = capsys.readouterr().out
    assert f"1. War -- Tol ▤900 {ISBN13}\n" in out
    assert out.endswith("2. Peace -- ? ▤? -\n")


def test_add_and_attach(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: Out
) -> None:
    info = BookInfo(title="War", author="Tol", pages=900, isbn=ISBN13)
    monkeypatch.setattr(_grading, "lookup_book", lambda _paths, _isbn: info)
    assert _cli.main(["add", ISBN13, "--pages", "1225"]) == 0
    assert capsys.readouterr().out == f"{GLYPH[OK]} {GLYPH[BOOK]} War -- Tol ▤1225\n"

    book = tmp_path / "war.txt"
    book.write_text(LONG_TEXT, encoding="utf-8")
    assert _cli.main(["add", ISBN13, "--file", str(book)]) == 0
    lines = capsys.readouterr().out.splitlines()
    assert lines[1:] == [GLYPH[OK]]


def test_attach_without_a_book(tmp_path: Path, capsys: Out) -> None:
    assert _cli.main(["attach", str(tmp_path / "war.txt")]) == 1
    assert capsys.readouterr().err == f"{GLYPH[NO]}\n"


def test_pages(bg_paths: Paths, capsys: Out) -> None:
    assert _cli.main(["pages", "300"]) == 1
    assert capsys.readouterr().err == f"{GLYPH[BOOK]} ?\n"
    add_book(bg_paths, pages=None)
    assert _cli.main(["pages", "412"]) == 0
    assert capsys.readouterr().out == f"{GLYPH[OK]} {GLYPH[BOOK]} War -- Tol ▤412\n"


def test_process_now_needs_the_sandbox(
    monkeypatch: pytest.MonkeyPatch, capsys: Out
) -> None:
    monkeypatch.delenv("BOOK_GUARD_ROOT", raising=False)
    assert _cli.main(["process", "--now", "2026-10-05T18:00:00+00:00"]) == 2
    assert capsys.readouterr().err == f"{GLYPH[NO]}\n"


def test_process_reports_what_it_read(
    bg_paths: Paths, tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: Out
) -> None:
    monkeypatch.setenv("BOOK_GUARD_ROOT", str(tmp_path / "sandbox"))
    seen: list[float | None] = []
    read = [
        rec("page", 42, T0),
        rec("isbn", None, T0, kind="isbn", isbn=ISBN13),
        replace(
            rec("late", None, T0, kind="other", status=REJECTED),
            reason="uploaded too late",
        ),
    ]

    def fake_process(paths: Paths, *, now: float | None) -> Any:
        seen.append(now)
        return InboxResult(read=read, duplicates=1, deferred=["x"]), snapshot(paths)

    monkeypatch.setattr(_cli, "process", fake_process)
    assert _cli.main(["process", "--now", "2026-10-05T18:00:00+00:00"]) == 0
    assert _cli.main(["process"]) == 0
    assert seen == [
        datetime.fromisoformat("2026-10-05T18:00:00+00:00").timestamp(),
        None,
    ]
    out = capsys.readouterr().out.splitlines()
    assert out[:4] == [
        f"{GLYPH[CAMERA]} 3  {GLYPH[OVERLAP]} 1  ◷ 1",
        f"  page.jpg {GLYPH[OK]} 42",
        f"  isbn.jpg {GLYPH[OK]} {ISBN13}",
        f"  late.jpg {GLYPH[NO]}",
    ]
    assert not (tmp_path / "sandbox").exists()  # the override still wins


def test_status_text_and_json(bg_paths: Paths, capsys: Out) -> None:
    add_book(bg_paths)
    assert _cli.main(["status"]) == 0
    assert f"{GLYPH[BOOK]} War -- Tol ▤300" in capsys.readouterr().out
    assert _cli.main(["status", "--json"]) == 0
    doc = json.loads(capsys.readouterr().out)
    assert doc["book"]["isbn"] == ISBN13


def test_quiz_nothing_waiting(capsys: Out) -> None:
    assert _cli.main(["quiz"]) == 0
    assert capsys.readouterr().out == f"{GLYPH[OK]}\n"


@pytest.mark.parametrize(
    ("stdin", "summary"),
    [
        ("first line\nsecond\n\nignored\n", "first line second"),
        ("eof only", "eof only"),
    ],
)
@pytest.mark.parametrize(("passed", "code"), [(True, 0), (False, 1)])
def test_quiz_grades(
    bg_paths: Paths,
    monkeypatch: pytest.MonkeyPatch,
    capsys: Out,
    stdin: str,
    summary: str,
    *,
    passed: bool,
    code: int,
) -> None:
    seed_photos(bg_paths, *quiz_pair())
    got: list[tuple[str, str]] = []

    def quiz_one(_paths: Paths, _view: Any, text: str, *, model: str) -> Verdict:
        got.append((text, model))
        return Verdict(
            passed=passed, feedback="Noted.", missing=() if passed else ("the ending",)
        )

    monkeypatch.setattr(_cli, "quiz_one", quiz_one)
    monkeypatch.setattr(sys, "stdin", io.StringIO(stdin))
    assert _cli.main(["quiz", "--model", "sonnet"]) == code
    assert got == [(summary, "sonnet")]
    out = capsys.readouterr().out
    assert out.startswith(f"{GLYPH[BOOK]} ? 10-11")
    assert (GLYPH[OK] in out, "  - the ending\n" in out) == (passed, not passed)


def test_quiz_grader_down(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, capsys: Out
) -> None:
    seed_photos(bg_paths, *quiz_pair())
    add_book(bg_paths)

    def down(*_args: object, **_kwargs: object) -> Verdict:
        msg = "offline"
        raise ClaudeUnavailableError(msg)

    monkeypatch.setattr(_cli, "quiz_one", down)
    monkeypatch.setattr(sys, "stdin", io.StringIO("text\n\n"))
    assert _cli.main(["quiz", "--session", "session:nope"]) == 0  # not waiting
    assert _cli.main(["quiz"]) == 1
    captured = capsys.readouterr()
    assert "War -- Tol 10-11" in captured.out
    assert captured.err == f"{GLYPH[WARN]}\n"


def test_lock(monkeypatch: pytest.MonkeyPatch, capsys: Out) -> None:
    assert _cli.main(["lock", "--production", "--today", "2026-10-15"]) == 2
    assert capsys.readouterr().err == f"{GLYPH[NO]}\n"
    calls: list[dict[str, Any]] = []

    def run_gate(_paths: Paths, **kwargs: Any) -> int:
        calls.append(kwargs)
        return 0

    monkeypatch.setattr(_cli, "run_gate", run_gate)
    assert _cli.main(["lock", "--today", "2026-10-15"]) == 0
    assert _cli.main(["lock", "--production"]) == 0
    assert calls == [
        {"production": False, "today": date(2026, 10, 15)},
        {"production": True, "today": None},
    ]


def test_no_command_is_a_usage_error(capsys: Out) -> None:
    with pytest.raises(SystemExit) as exc:
        _cli.main([])
    assert (exc.value.code, "usage: book-guard" in capsys.readouterr().err) == (2, True)


def test_python_dash_m(monkeypatch: pytest.MonkeyPatch, capsys: Out) -> None:
    monkeypatch.setattr(sys, "argv", ["book-guard", "status"])
    monkeypatch.delitem(sys.modules, "book_guard.__main__", raising=False)
    with pytest.raises(SystemExit) as exc:
        runpy.run_module("book_guard", run_name="__main__")
    assert exc.value.code == 0
    assert f"{GLYPH[BOOK]} ?" in capsys.readouterr().out


def test_add_with_no_source_reachable_fails(
    monkeypatch: pytest.MonkeyPatch, capsys: Out
) -> None:
    def offline(_paths: Paths, _isbn: str) -> None:
        msg = "no book source answered"
        raise UnavailableError(msg)

    monkeypatch.setattr(_grading, "lookup_book", offline)
    assert _cli.main(["add", ISBN13]) == 1
    assert capsys.readouterr().out == f"{GLYPH[NO]}\n"
