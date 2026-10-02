# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``book-guard`` / ``python -m book_guard``: every entry point."""

from __future__ import annotations

import argparse
from datetime import date, datetime
import json
import logging
import os
from pathlib import Path
import sys
from typing import TYPE_CHECKING, Final, TextIO

from book_guard._actions import next_quiz, process
from book_guard._attach import attach
from book_guard._books import current, register
from book_guard._booktext import BookTextError
from book_guard._claude import DEFAULT_MODEL, ClaudeUnavailableError
from book_guard._grading import quiz_one, register_isbn
from book_guard._ledger import load
from book_guard._lock import run_gate
from book_guard._openlibrary import BookInfo, search_title
from book_guard._paths import paths
from book_guard._render import session_line, status_lines
from book_guard._state import snapshot
from book_guard._state_json import to_json

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence


_logger: Final = logging.getLogger(__name__)


def _say(*parts: object, file: TextIO | None = None) -> None:
    """One line to the terminal -- the CLI's only output channel.

    ``file`` defaults to the stream ``sys.stdout`` is *now*, not at import,
    so a redirected stdout (tests, pipes set up late) is honoured.
    """
    (file or sys.stdout).write(" ".join(str(p) for p in parts) + "\n")


def _cmd_search(args: argparse.Namespace) -> int:
    try:
        hits = search_title(args.title)
    except OSError as exc:
        _logger.warning("title search failed: %s", exc)
        _say(f"Open Library unreachable: {exc}", file=sys.stderr)
        return 1
    if not hits:
        _say("No matches.")
        return 1
    for i, hit in enumerate(hits, 1):
        pages = hit.pages or "?"
        _say(
            f"{i}. {hit.title} -- {hit.author or '?'} ({pages} p) "
            f"ISBN {hit.isbn or '-'}"
        )
    _say("\nRegister one with: book-guard add <ISBN>")
    return 0


def _cmd_add(args: argparse.Namespace) -> int:
    ok, message = register_isbn(paths(), args.isbn, pages=args.pages)
    _say(message)
    if not ok:
        return 1
    if args.file:
        return _cmd_attach(args)
    return 0


def _cmd_attach(args: argparse.Namespace) -> int:
    try:
        _say(attach(paths(), Path(args.file).expanduser()))
    except BookTextError as exc:
        _logger.warning("attach failed: %s", exc)
        _say(f"Not attached: {exc}", file=sys.stderr)
        return 1
    return 0


def _cmd_pages(args: argparse.Namespace) -> int:
    active = paths()
    book = current(load(active.ledger, active.key_file))
    if book is None:
        _say("No book registered yet.", file=sys.stderr)
        return 1
    info = BookInfo(
        title=book.title, author=book.author, pages=args.pages, isbn=book.isbn
    )
    _say(f"{register(active, info).label}: last page {args.pages}")
    return 0


def _cmd_process(args: argparse.Namespace) -> int:
    if args.now and not os.environ.get("BOOK_GUARD_ROOT"):
        _say("--now only works in a BOOK_GUARD_ROOT sandbox", file=sys.stderr)
        return 2
    result, _snap = process(paths(), now=args.now.timestamp() if args.now else None)
    _say(
        f"read {len(result.read)}, duplicates {result.duplicates}, "
        f"deferred {len(result.deferred)}"
    )
    for record in result.read:
        detail = record.reason if record.status != "ok" else f"page {record.page}"
        _say(f"  {record.name}: {record.kind} {detail or record.isbn or ''}")
    return 0


def _cmd_status(args: argparse.Namespace) -> int:
    active = paths()
    snap = snapshot(active)
    if args.json:
        _say(json.dumps(to_json(active, snap), indent=1, ensure_ascii=False))
    else:
        _say("\n".join(status_lines(snap, recent=12)))
    return 0


def _read_summary() -> str:
    _say("Summary (3-5 sentences; finish with an empty line):")
    lines: list[str] = []
    for line in sys.stdin:
        if not line.strip():
            break
        lines.append(line.rstrip("\n"))
    return " ".join(lines)


def _cmd_quiz(args: argparse.Namespace) -> int:
    active = paths()
    view = next_quiz(active, session_id=args.session)
    if view is None:
        _say("Nothing waiting for a summary.")
        return 0
    _say(
        f"{view.book.label if view.book else 'Unregistered book'}: {session_line(view)}"
    )
    try:
        verdict = quiz_one(active, view, _read_summary(), model=args.model)
    except ClaudeUnavailableError as exc:
        _logger.warning("grader unavailable: %s", exc)
        _say(f"Grader unavailable ({exc}); the session stays open.", file=sys.stderr)
        return 1
    _say(("PASSED: " if verdict.passed else "FAILED: ") + verdict.feedback)
    return 0 if verdict.passed else 1


def _cmd_lock(args: argparse.Namespace) -> int:
    if args.today and args.production:
        _say("--today is for demos only", file=sys.stderr)
        return 2
    return run_gate(paths(), production=args.production, today=args.today)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="book-guard", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    commands: list[tuple[str, str, Callable[[argparse.Namespace], int]]] = [
        ("search", "find a book's ISBN by title", _cmd_search),
        ("add", "register the book you are reading", _cmd_add),
        ("pages", "set the current book's last page", _cmd_pages),
        ("attach", "attach the current book's ebook file (any format)", _cmd_attach),
        ("process", "read new photos from the inbox", _cmd_process),
        ("status", "show pace, sessions and what to do next", _cmd_status),
        ("quiz", "write the summary for a finished session", _cmd_quiz),
        ("lock", "run the gate (locks only when behind pace)", _cmd_lock),
    ]
    subs = {}
    for name, help_text, handler in commands:
        subs[name] = sub.add_parser(name, help=help_text)
        subs[name].set_defaults(handler=handler)
    subs["search"].add_argument("title")
    subs["add"].add_argument("isbn")
    subs["add"].add_argument("--pages", type=int, help="override the last page")
    subs["add"].add_argument("--file", help="its ebook file (epub, pdf, mobi, ...)")
    subs["attach"].add_argument("file")
    subs["pages"].add_argument("pages", type=int)
    subs["process"].add_argument(
        "--now",
        type=datetime.fromisoformat,
        help="sandbox demo: pretend upload-check time",
    )
    subs["status"].add_argument(
        "--json", action="store_true", help="the app's state.json"
    )
    subs["quiz"].add_argument(
        "--session", help="grade this session id (default: oldest)"
    )
    subs["quiz"].add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help="grader for this run only (default: haiku)",
    )
    subs["lock"].add_argument("--production", action="store_true")
    subs["lock"].add_argument(
        "--today", type=date.fromisoformat, help="demo: pretend date"
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Parse ``argv`` and run one command."""
    logging.basicConfig(level=logging.INFO, format="book-guard: %(message)s")
    args = _parser().parse_args(argv)
    handler: Callable[[argparse.Namespace], int] = args.handler
    return handler(args)
