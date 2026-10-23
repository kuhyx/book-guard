# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The photo-session grading prompt, pinned byte for byte.

``scripts/grader_suite.py`` measured these exact prompts on real models.
In-app (ebook) reading added its own prompt branch; the photo prompt --
with or without the book's text, first summary or rewrite, Haiku or the
local fallback's reminder -- must not move by a single byte without the
suite being re-run.
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
    "photos": "824fd0544f10d1bf47e6b412285f7f1c42fa699771bd6acbcaeecee8dcd6baa1",
    "photos+span": "ac001d00c69a12a7aafc13b40eb70f3f0506d334a1ae64bc25072d5c353eca9b",
    "rewrite": "e7e48c23f6cb337fc5d8c8843d18ed1fd8ef8f761369e0a267eed81e9a4a0dd1",
    "photos+local": "bc7e55dd2765640cc7c91011412fb4cc4618e6d22e00123784817b3dc173f6d9",
}


@pytest.mark.parametrize("case", sorted(CASES))
def test_the_photo_prompt_is_byte_identical(case: str) -> None:
    context, local = CASES[case]
    prompt = build_prompt(BOOK, SESSION, SUMMARY, context)
    if local:
        prompt += LOCAL_REMINDER
    assert hashlib.sha256(prompt.encode()).hexdigest() == PINNED[case]
