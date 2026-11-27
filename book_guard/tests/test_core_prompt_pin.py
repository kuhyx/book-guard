# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The photo-session grading prompt, pinned byte for byte.

``scripts/grader_suite.py`` measured these exact prompts on real models.
In-app (ebook) reading added its own prompt branch; the photo prompt --
with or without the book's text, first summary or rewrite, Haiku or the
local fallback's reminder -- must not move by a single byte without the
suite being re-run.

Moved once without a re-run (2026-11-11, both ends of a paper session count):
the page range now ends on the stop page (``10-20``, 11 pages), and the stop
page is "the last page read" instead of "not read". Re-run
``scripts/grader_suite.py`` to re-measure.

Moved 2026-11-27 with a re-run (kuhy: all 7 real fails were false): a
summary fails only off-topic or for a contradiction (``_prompt._rules``),
a fail always names 1-3 topics, a rewrite passes on one covered point.
"""

from __future__ import annotations

from datetime import UTC, datetime
import hashlib

import pytest

from book_guard._books import Book
from book_guard._photos import PhotoRecord
from book_guard._prompt import LOCAL_REMINDER, Context, build_prompt
from book_guard._sessions import Session

T = datetime(2026, 10, 5, 16, 0, tzinfo=UTC)


def _photo(name: str, page: int, minute: int) -> PhotoRecord:
    taken = T.replace(minute=minute).isoformat()
    return PhotoRecord(
        sha=hashlib.sha256(name.encode()).hexdigest(),
        name=f"{name}.jpg",
        taken_at=taken,
        uploaded_at=taken,
        kind="page",
        page=page,
        text=f"text of {name} on page {page}",
    )


BOOK = Book("9780140449136", "War", "Tol", 300, T)
SESSION = Session(
    _photo("start", 10, 0), _photo("end", 20, 30), 15, _photo("check", 15, 40)
)
SUMMARY = "They walked to the river and argued about the money all evening."

CASES = {
    "photos": (Context(), False),
    "photos+span": (Context(span="the book's own words"), False),
    "rewrite": (Context(checklist=("the river", "the money")), False),
    "photos+local": (Context(), True),
}

PINNED = {
    "photos": "694674e7120da76ce4c0f2dede178fb8c5f210afbb299a763378d71443fe4a05",
    "photos+span": "79edc1709be8cb9303500f0ce017bd675f33e1bb0d028f58fd488755e5040cd3",
    "rewrite": "1bfb4e6735f665a27baca9aa8ac1c194f8d045696a941a3e67c4e526ab2e5d38",
    "photos+local": "8c21283aea629ef9439f9df281db09cfde5b46fbb89987000f8d4ae3df7bf307",
}


@pytest.mark.parametrize("case", sorted(CASES))
def test_the_photo_prompt_is_byte_identical(case: str) -> None:
    context, local = CASES[case]
    prompt = build_prompt(BOOK, SESSION, SUMMARY, context)
    if local:
        prompt += LOCAL_REMINDER
    assert hashlib.sha256(prompt.encode()).hexdigest() == PINNED[case]


def test_a_session_without_a_check_photo_names_only_start_and_stop() -> None:
    """From the drop of the check page a session has two photos."""
    two = Session(_photo("start", 10, 0), _photo("end", 20, 30), 15)
    prompt = build_prompt(BOOK, two, SUMMARY)
    assert (
        "They photographed the page they started on and the page where they"
        " STOPPED -- the stop page was read too." in prompt
    )
    assert "check page" not in prompt
