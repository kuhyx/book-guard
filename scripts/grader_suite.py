# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Adversarial check of the vision reader and the grader on one model.

Runs against a BOOK_GUARD_ROOT sandbox holding the Treasure Island demo
session p. 40-62 (see scripts/demo_photos.py). Writes nothing: it calls
``read_photo`` and ``grade`` directly and prints a pass/fail table, exiting
non-zero if any case lands on the wrong side.

    BOOK_GUARD_ROOT=.demo python3 scripts/grader_suite.py [MODEL]
"""

from __future__ import annotations

import sys
from typing import TYPE_CHECKING

from book_guard import _ledger, _photos
from book_guard._anchor import find_span
from book_guard._books import book_at
from book_guard._claude import ask
from book_guard._paths import paths
from book_guard._photo import open_photo
from book_guard._quiz import grade
from book_guard._sessions import build_sessions
from book_guard._vision import read_photo

if TYPE_CHECKING:
    from book_guard._books import Book
    from book_guard._paths import Paths
    from book_guard._photos import PhotoRecord
    from book_guard._sessions import Session

_DEMO_START_PAGE = 40

GENUINE = (
    "Captain Smollett, worried about mutiny, lets the crew go ashore for the "
    "afternoon, and Jim impulsively slips into one of the boats and runs off "
    "into the island alone. Hiding in the woods he sees Long John Silver try "
    "to win over the honest sailor Tom, and when Tom refuses Silver kills him, "
    "so Jim flees in terror and meets the marooned Ben Gunn. Then the doctor "
    "takes over the story: he and Hunter find the log stockade, and the loyal "
    "party abandons the Hispaniola, ferrying stores in the jolly-boat and "
    "dumping the rest of the powder overboard."
)
VAGUE = (
    "The story continues with the characters on the island. There is some "
    "tension between the people and things happen that move the plot forward. "
    "Some characters talk about what to do next and there is a bit of adventure."
)
WRONG_PART = (
    "Jim is a prisoner in the stockade and Silver protects him from the other "
    "pirates, who hand Silver the black spot. On the treasure hunt they find a "
    "skeleton pointing the way and a voice singing Flint's song terrifies them. "
    "They reach the pit only to find it empty, and Ben Gunn had moved the "
    "treasure to his cave long before."
)
POLISH = (
    "Kapitan Smollett, obawiając się buntu, pozwala załodze zejść na ląd, a Jim "
    "ukradkiem wskakuje do jednej z łodzi i ucieka w głąb wyspy. W lesie widzi, "
    "jak Długi John Silver namawia uczciwego marynarza Toma do buntu, a gdy ten "
    "odmawia, Silver go zabija. Jim w przerażeniu ucieka i spotyka Bena Gunna, "
    "porzuconego na wyspie. Potem narrację przejmuje doktor: lojalna część "
    "załogi opuszcza Hispaniolę i przewozi zapasy do blokhauzu."
)


def _out(*parts: object) -> None:
    """A report line on stdout (a script's output, not a log)."""
    sys.stdout.write(" ".join(str(x) for x in parts) + "\n")


def _paraphrase_of_photos(texts: list[str]) -> str:
    """The cheat: restate only what the photographed pages visibly say."""
    return (
        "On the page where I started, "
        + texts[0][:280]
        + " Later on, "
        + texts[1][:280]
        + " At the end, "
        + texts[2][:280]
    )


def _smart_cheat(photos: list[PhotoRecord], model: str) -> str:
    """The realistic cheat: a summary built ONLY from the photographed pages.

    Fluent, as someone who skimmed three pages would write it.
    """
    excerpts = "\n\n".join(p.text for p in photos)
    answer = ask(
        "You write short, natural book-club summaries.",
        "Write a natural 4-sentence summary of the reading below, as if you "
        "had read the whole stretch. Use ONLY facts from these excerpts. "
        'Answer with the line {"ok": true}, then ---TEXT---, then the '
        "summary.\n\n" + excerpts,
        model=model,
    )
    return str(answer["text"])


def _vision_failures(active: Paths, session: Session, model: str) -> int:
    """Re-read each evidence photo; count page numbers read wrong."""
    failures = 0
    for record in session.evidence:
        path = next(active.processed.glob(f"{record.sha[:12]}-*"))
        photo = open_photo(path)
        if photo is None:
            msg = f"{path} is not a readable photo"
            raise SystemExit(msg)
        seen = read_photo(photo.jpeg_b64, model=model).page_number
        ok = seen == record.page
        failures += not ok
        _out(f"vision  p.{record.page}: read {seen}  {'ok' if ok else 'WRONG'}")
    return failures


def _grade_failures(
    book: Book | None, session: Session, span_text: str, model: str
) -> int:
    """Grade every case; count verdicts on the wrong side."""
    cases = [
        ("genuine", GENUINE, True),
        ("vague", VAGUE, False),
        (
            "photo-paraphrase",
            _paraphrase_of_photos([p.text for p in session.evidence]),
            False,
        ),
        ("wrong-part", WRONG_PART, False),
        ("smart-photo-cheat", _smart_cheat(session.evidence, model), False),
        ("polish", POLISH, True),
    ]
    failures = 0
    for name, summary, want in cases:
        verdict = grade(book, session, summary, model=model, span=span_text)
        ok = verdict.passed == want
        failures += not ok
        _out(
            f"grade   {name:17} want {'pass' if want else 'fail'} got "
            f"{'pass' if verdict.passed else 'fail'}  {'ok' if ok else 'WRONG'}"
            f"  -- {verdict.feedback[:110]}"
        )
    return failures


def main() -> int:
    """Run every case; exit 1 if any landed on the wrong side."""
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    model = args[0] if args else "haiku"
    active = paths()
    ledger = _ledger.load(active.ledger, active.key_file)
    records = _photos.load(active.photos)
    session = next(
        s
        for s in build_sessions(_photos.usable_pages(records))
        if s.start.page == _DEMO_START_PAGE
    )
    book = book_at(ledger, session.end.taken)
    use_span = book is not None and "--no-span" not in sys.argv
    span = find_span(active, book.isbn, session) if book and use_span else None
    _out("book text:", span.reason if span else "not used", span.scores if span else "")
    failures = _vision_failures(active, session, model)
    failures += _grade_failures(book, session, span.text if span else "", model)
    _out(f"{failures} case(s) on the wrong side ({model})")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
