# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The ``summary`` request: a verdict code, the pass flag and missing topics."""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _grading, _ledger
from book_guard._app_handlers import HANDLERS
from book_guard._grading import UNGRADED
from book_guard._quiz import Verdict
from book_guard._requests import Response, handle_requests
from book_guard.tests._flow_helpers import quiz_pair, seed_photos

if TYPE_CHECKING:
    from book_guard._paths import Paths


def _waiting(paths: Paths) -> str:
    """One session waiting for its summary; its id."""
    records = quiz_pair()
    seed_photos(paths, *records)
    return f"session:{records[0].sha[:16]}-{records[1].sha[:16]}"


def test_summary_for_a_stale_session(bg_paths: Paths) -> None:
    response = HANDLERS["summary"](bg_paths, {"session_id": "session:gone"})
    assert response == Response(ok=False, code="not_waiting")


@pytest.mark.parametrize(
    ("verdict", "expected"),
    [
        (
            Verdict(passed=True, feedback="Good."),
            Response(ok=True, code="passed", passed=True),
        ),
        (
            Verdict(passed=True, feedback=UNGRADED, ungraded=True),
            Response(ok=True, code="ungraded", passed=True),
        ),
        (
            Verdict(passed=False, feedback="Thin.", missing=("the marlin",)),
            Response(
                ok=True, code="failed", passed=False, data={"missing": ["the marlin"]}
            ),
        ),
        (
            Verdict(passed=False, feedback="Thin."),
            Response(ok=True, code="failed", passed=False),
        ),
    ],
)
def test_summary_grades_the_session(
    bg_paths: Paths,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
    verdict: Verdict,
    expected: Response,
) -> None:
    caplog.set_level(logging.INFO)
    sid = _waiting(bg_paths)
    monkeypatch.setattr(_grading, "grade", lambda *_a, **_k: verdict)
    response = HANDLERS["summary"](bg_paths, {"session_id": sid, "summary": "text"})
    assert response == expected
    (row,) = _ledger.load(bg_paths.ledger, bg_paths.key_file).verdicts()[sid]
    assert row.entry_id == sid
    # The sentence around the topics is the PC's, in its log.
    assert verdict.feedback in caplog.text


def test_a_summary_already_credited_says_so(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    sid = _waiting(bg_paths)
    monkeypatch.setattr(
        _grading, "grade", lambda *_a, **_k: Verdict(passed=True, feedback="Good.")
    )
    # Another pass credited the session between the snapshot and the write.
    monkeypatch.setattr(_grading, "record_verdict", lambda *_a, **_k: None)
    response = HANDLERS["summary"](bg_paths, {"session_id": sid, "summary": "text"})
    assert response == Response(ok=True, code="already_credited", passed=False)


def test_a_fail_without_topics_sends_no_data(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    sid = _waiting(bg_paths)
    monkeypatch.setattr(
        _grading, "grade", lambda *_a, **_k: Verdict(passed=False, feedback="Thin.")
    )
    bg_paths.requests.mkdir(parents=True)
    request = {"id": "req-0003", "type": "summary", "session_id": sid}
    (bg_paths.requests / "req-0003.json").write_text(json.dumps(request))
    assert handle_requests(bg_paths, HANDLERS) == 1
    reply: dict[str, Any] = json.loads(
        (bg_paths.responses / "req-0003.json").read_text()
    )
    assert reply == {"id": "req-0003", "ok": True, "code": "failed", "passed": False}
