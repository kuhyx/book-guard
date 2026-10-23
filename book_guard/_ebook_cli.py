# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``book-guard ebook-map``: rebuild the in-app reader's page map and show it.

The knots (ebook offset -> paper page) and how far each photographed page
lands from where the others predict it (leave-one-out, in pages) -- the
way to see how much an estimated "≈ p. N" can be trusted.
"""

from __future__ import annotations

import sys
from typing import TYPE_CHECKING

from book_guard import _ebook
from book_guard._books import current
from book_guard._ledger import load
from book_guard._paths import paths

if TYPE_CHECKING:
    import argparse


def _say(line: str) -> None:
    sys.stdout.write(line + "\n")


def cmd_ebook_map(_args: argparse.Namespace) -> int:
    """Refresh the current book's map and print it; 1 when there is none."""
    active = paths()
    _ebook.refresh(active)
    book = current(load(active.ledger, active.key_file))
    found = _ebook.load_map(active, book.isbn) if book else None
    if book is None or found is None:
        _say("No page map: attach the ebook and photograph 3+ pages of it.")
        return 1
    page_map = found.pages
    residuals = page_map.residuals
    rms = (sum(r * r for r in residuals) / len(residuals)) ** 0.5 if residuals else 0
    _say(
        f"{book.label}: {found.photos} photographed pages located,"
        f" {page_map.slope:.0f} characters a page, story {page_map.start}-"
        f"{page_map.end} of {found.chars}"
    )
    _say("knots (offset -> page):")
    for knot in page_map.knots:
        _say(f"  {knot.offset:>9} -> {knot.page:7.2f}")
    _say(f"leave-one-out error (pages): {list(residuals)}, RMS {rms:.2f}")
    return 0
