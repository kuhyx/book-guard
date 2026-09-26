# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Read-only MCP server: the gate's state and the current book's text.

Same three invariants as leetcode-guard's server:

**1. READ-ONLY.** No tool credits a session, grades a summary, registers a
book or unlocks anything. Grading happens only inside book-guard's own
grader (``book-guard quiz`` / the lock / the app), never because an agent
said so.

**2. stdout is the JSON-RPC channel.** Logging goes to stderr and nothing
here prints or imports the CLI.

**3. No secret leaves.** Nothing returns the HMAC key or the dufs login.

The book tools read the local index only (``book-guard attach``); they never
fetch anything.
"""

from __future__ import annotations

import logging
import sys
from typing import Any, Final

from mcp.server import MCPServer
from mcp.types import ToolAnnotations

from book_guard import _ledger
from book_guard._anchor import find_span
from book_guard._bookindex import load
from book_guard._books import current
from book_guard._embed import embed_queries
from book_guard._paths import paths
from book_guard._state import snapshot
from book_guard._state_json import to_json

logging.basicConfig(stream=sys.stderr, level=logging.WARNING)
_logger: Final = logging.getLogger(__name__)

mcp: Final = MCPServer("book-guard")

_READS_ONLY: Final = ToolAnnotations(
    read_only_hint=True,
    idempotent_hint=True,
    open_world_hint=False,
)
_MAX_TOP: Final = 10


@mcp.tool(title="Reading gate status", annotations=_READS_ONLY)
def get_status() -> dict[str, Any]:
    """Pace, the current book, recent sessions and what is pending.

    The same JSON the app reads (state.json), computed fresh.
    """
    active = paths()
    return to_json(active, snapshot(active))


@mcp.tool(title="Search the current book", annotations=_READS_ONLY)
def search_book(query: str, top: int = 5) -> dict[str, Any]:
    """Passages of the current book's attached ebook most similar to ``query``.

    Multilingual: a Polish query finds the English passage and vice versa.
    Returns an error string when no book or no book file is attached.
    """
    active = paths()
    book = current(_ledger.load(active.ledger, active.key_file))
    index = load(active, book.isbn) if book else None
    if book is None or index is None:
        return {"error": "no book file attached (book-guard attach FILE)"}
    hits = index.search(embed_queries(active, [query]), top=max(1, min(top, _MAX_TOP)))[
        0
    ]
    return {
        "book": book.label,
        "passages": [
            {
                "score": round(h.score, 3),
                "offset": h.start,
                "text": index.text[h.start : h.end],
            }
            for h in hits
        ],
    }


@mcp.tool(title="Book text a session covers", annotations=_READS_ONLY)
def session_text(session_id: str) -> dict[str, Any]:
    """The anchored book text between one session's start and end photos.

    Exactly what the grader reads. ``reason`` says why it is empty when the
    photos could not be anchored in the book file.
    """
    active = paths()
    view = next(
        (v for v in snapshot(active).sessions if v.session.session_id == session_id),
        None,
    )
    if view is None:
        return {"error": f"no session {session_id!r}"}
    span = find_span(active, view.book.isbn if view.book else "", view.session)
    return {"reason": span.reason, "scores": list(span.scores), "text": span.text}


def main() -> None:
    """Serve over stdio."""
    mcp.run()


if __name__ == "__main__":
    main()
