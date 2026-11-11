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
    "photos": "43eac27e604c0130d5c7521b2083186e29bdc8429a3e22655f0483914d1d67ae",
    "photos+span": "d5b2541b2a6105a66f1a5db894551087af197829e4803f5e7bae0263b6111335",
    "rewrite": "5e49ca3ddbaa949a4e1511b4461fa362be6b2edb8f27c7e0985da89ea107a5c4",
    "photos+local": "b03af5706f073fc8bec58cdb32a4a3afa531f5fd0d58a7bd5493a1865a35dfa8",
}


@pytest.mark.parametrize("case", sorted(CASES))
def test_the_photo_prompt_is_byte_identical(case: str) -> None:
    context, local = CASES[case]
    prompt = build_prompt(BOOK, SESSION, SUMMARY, context)
    if local:
        prompt += LOCAL_REMINDER
    assert hashlib.sha256(prompt.encode()).hexdigest() == PINNED[case]
