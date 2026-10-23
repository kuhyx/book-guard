# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""What every grading prompt ends with: the answer and the shared rules.

The answer format, what a fail names, and the rules that hold whatever the
evidence -- photos or the text read in the app. Split from
:mod:`book_guard._prompt` so the in-app prompt
(:mod:`book_guard._prompt_ebook`) shares them word for word.
"""

from __future__ import annotations

from typing import Final

MAX_MISSING: Final = 3

MISSING: Final = (
    f'On a FAIL, list in "missing" 1-{MAX_MISSING} things from THESE pages'
    " whose mention would make you accept it: main events, not small details."
    ' Name each as a topic (e.g. "what he did after arriving in the village"),'
    " never the answer itself. Leave it empty only if no addition could rescue"
    " the summary (it describes another book or another part of it)."
)

ANSWER: Final = (
    'Answer ONLY with JSON: {"passed": true|false, "feedback": "<one or two'
    ' sentences addressed to the reader>", "missing": ["<topic>", ...]}'
)

UNVERIFIABLE: Final = (
    " Anything in the summary you cannot check against the text above is NEVER"
    " a reason to fail -- it is expected, it comes from pages you were not"
    " given, and it counts FOR the reader. Your own memory of the book is not"
    " evidence against them either. Never call a claim 'unsupported',"
    " 'unverified' or 'not in the pages' as a reason to fail."
)


def rewrite_rules(checklist: tuple[str, ...]) -> list[str]:
    """How a rewrite is judged: the previous grading's promise, nothing new."""
    return [
        (
            "This is a REWRITE. The previous summary failed, and the grader"
            " promised to accept it once it also covered:"
        ),
        *(f"- {item}" for item in checklist),
        (
            "PASS if the rewrite says something about what happens for each"
            " point -- a sentence is enough, in the reader's own words, any"
            " language. Judge it generously: this is not a quiz with one right"
            " answer, and partial, imprecise or misremembered details still"
            " cover a point. Do not add requirements beyond this list, never"
            " judge pace, time or the stop page, and never fail for anything"
            " you cannot verify."
        ),
        (
            "A point is NOT covered when the rewrite only names it (e.g. 'I"
            " also read about X') without saying anything about what happens."
            ' FAIL only then, and list in "missing" exactly the points still'
            " missing."
        ),
    ]
