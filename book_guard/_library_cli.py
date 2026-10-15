# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``book-guard library``: every book, its sessions, full summaries and notes.

book-guard library [--isbn X] [--export md]
"""

from __future__ import annotations

import sys
from typing import TYPE_CHECKING

from book_guard import _library_text as library_text
from book_guard._library import build as build_library
from book_guard._paths import paths
from book_guard._state import snapshot
from book_guard._vision import normalise_isbn

if TYPE_CHECKING:
    import argparse


def configure(parser: argparse.ArgumentParser) -> None:
    """The ``library`` subcommand's flags."""
    parser.add_argument("--isbn", help="one book in detail")
    parser.add_argument("--export", choices=["md"], help="as Markdown")


def _out(text: str, *, err: bool = False) -> None:
    (sys.stderr if err else sys.stdout).write(text + "\n")


def cmd_library(args: argparse.Namespace) -> int:
    """Print the library (or one book) as text or Markdown."""
    active = paths()
    doc = build_library(active, snapshot(active))
    if args.isbn:
        isbn = normalise_isbn(args.isbn) or args.isbn
        doc["books"] = [b for b in doc["books"] if b["isbn"] == isbn]
        if not doc["books"]:
            _out(f"No registered book has ISBN {args.isbn}.", err=True)
            return 1
    if args.export == "md":
        _out(library_text.markdown(doc).rstrip("\n"))
    elif args.isbn:
        _out("\n".join(library_text.book_detail(doc["books"][0])))
    else:
        _out("\n".join(library_text.library_lines(doc)))
    return 0
