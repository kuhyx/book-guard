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
    f'On a FAIL, always list in "missing" 1-{MAX_MISSING} main events of THESE'
    " pages that a summary of them would be about, so the reader sees which"
    ' part you expected. Name each as a topic (e.g. "what he did after'
    ' arriving in the village"), never the answer itself.'
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
    """How a rewrite is judged: like a first summary, off-topic only.

    The checklist stays (it shows which part was expected); a rewrite that
    only names its points passed nothing before 2026-11-27 and passes now:
    failing it was a fail for missing details (2914bcee#2, a false reject).
    """
    return [
        (
            "This is a REWRITE. The previous summary failed, and the grader"
            " promised to accept it once it also covered:"
        ),
        *(f"- {item}" for item in checklist),
        (
            "PASS unless the rewrite is still off-topic (about another book or"
            " another part of this one: it touches none of these points) or it"
            " clearly contradicts the text. A sentence on a point, a mention of"
            " it, partial or misremembered details: all fine, in the reader's"
            " own words and any language (kuhy, 2026-11-24: a fail for missing"
            " details is never a real reason). Never judge pace, time or the"
            " stop page, and never fail for anything you cannot verify."
        ),
        ('On a FAIL, list in "missing" the points it still does not touch.'),
    ]
