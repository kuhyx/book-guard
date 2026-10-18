# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The Claude outage flag: gone the instant it is no longer true."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta, timezone
import json
from typing import TYPE_CHECKING
from zoneinfo import ZoneInfo

import pytest

from book_guard import _errlog, _local, _quiz
from book_guard._claude import ClaudeUnavailableError
from book_guard._state import snapshot
from book_guard._state_json import to_json
from book_guard.tests._flow_helpers import make_book, only_session, quiz_pair

if TYPE_CHECKING:
    from book_guard._paths import Paths

WARSAW = ZoneInfo("Europe/Warsaw")
SINCE = datetime(2026, 10, 17, 16, 25, tzinfo=WARSAW)
LIMIT = (
    "claude exited 1: You've hit your session limit · resets 4:40pm "
    "(Europe/Warsaw) (API status 429)"
)


def _flag(paths: Paths) -> dict[str, object]:
    flag: dict[str, object] = json.loads(paths.claude_down.read_text(encoding="utf-8"))
    return flag


@pytest.mark.parametrize(
    ("error", "until"),
    [
        (LIMIT, datetime(2026, 10, 17, 16, 40, tzinfo=WARSAW)),
        ("resets 4pm", datetime(2026, 10, 18, 16, 0, tzinfo=WARSAW)),
        ("Resets 16:40 (UTC)", datetime(2026, 10, 17, 16, 40, tzinfo=UTC)),
        ("resets 12am", datetime(2026, 10, 18, 0, 0, tzinfo=WARSAW)),
        ("resets 12:30pm", datetime(2026, 10, 18, 12, 30, tzinfo=WARSAW)),
        ("resets 4:25pm", datetime(2026, 10, 18, 16, 25, tzinfo=WARSAW)),
    ],
)
def test_reset_time_is_parsed_to_until(error: str, until: datetime) -> None:
    """The next such wall-clock time after the failure, in the named zone."""
    assert _errlog.reset_at(error, SINCE) == until


@pytest.mark.parametrize(
    "error",
    [
        "claude exited 1: Claude AI usage limit reached",
        "resets Oct 20, 4pm",
        "resets 4",
        "resets 25:00",
        "resets 4:61pm",
        "resets 13pm",
        "resets 0am",
        "resets 4:40pm (Mars/Olympus)",
    ],
)
def test_unparseable_reset_has_no_until(error: str) -> None:
    assert _errlog.reset_at(error, SINCE) is None


def test_failure_stores_until(bg_paths: Paths) -> None:
    _errlog.claude_failed(bg_paths, LIMIT, now=SINCE)
    flag = _flag(bg_paths)
    assert flag["since"] == SINCE.isoformat(timespec="seconds")
    assert flag["until"] == "2026-10-17T16:40:00+02:00"
    outage = _errlog.claude_outage(bg_paths, SINCE + timedelta(minutes=14))
    assert outage == _errlog.Outage(str(flag["since"]), str(flag["until"]))


def test_unparseable_failure_stores_no_until(bg_paths: Paths) -> None:
    _errlog.claude_failed(bg_paths, "timed out", now=SINCE)
    assert "until" not in _flag(bg_paths)
    later = SINCE + timedelta(days=3)
    outage = _errlog.claude_outage(bg_paths, later)
    assert outage is not None
    assert outage.until is None


def test_an_expired_flag_is_absent_and_removed(bg_paths: Paths) -> None:
    _errlog.claude_failed(bg_paths, LIMIT, now=SINCE)
    reset = datetime(2026, 10, 17, 16, 40, tzinfo=WARSAW)
    assert _errlog.claude_outage(bg_paths, reset - timedelta(seconds=1))
    assert _errlog.claude_outage(bg_paths, reset) is None
    assert not bg_paths.claude_down.exists()
    assert _errlog.claude_down_since(bg_paths) is None


def test_an_expired_flag_does_not_block_a_new_outage(bg_paths: Paths) -> None:
    _errlog.claude_failed(bg_paths, LIMIT, now=SINCE)
    later = SINCE + timedelta(days=1)
    _errlog.claude_failed(bg_paths, LIMIT, now=later)  # file still there
    assert _flag(bg_paths)["since"] == later.isoformat(timespec="seconds")
    assert _flag(bg_paths)["until"] == "2026-10-18T16:40:00+02:00"


def test_a_live_flag_keeps_since_and_learns_the_reset(bg_paths: Paths) -> None:
    _errlog.claude_failed(bg_paths, "timed out", now=SINCE)
    _errlog.claude_failed(bg_paths, LIMIT, now=SINCE + timedelta(minutes=5))
    flag = _flag(bg_paths)
    assert flag["since"] == SINCE.isoformat(timespec="seconds")
    assert flag["until"] == "2026-10-17T16:40:00+02:00"
    _errlog.claude_failed(bg_paths, "resets 4:50pm", now=SINCE)
    assert _flag(bg_paths)["until"] == flag["until"]  # first reset wins


@pytest.mark.parametrize("until", ["soon", "2026-10-17T16:40:00"])
def test_unreadable_until_reads_as_no_until(bg_paths: Paths, until: str) -> None:
    """A garbled or zoneless ``until`` cannot be compared: no expiry."""
    bg_paths.claude_down.parent.mkdir(parents=True)
    flag = {"since": "2026-10-17T16:25:00+02:00", "until": until}
    bg_paths.claude_down.write_text(json.dumps(flag), encoding="utf-8")
    assert _errlog.claude_outage(bg_paths) == _errlog.Outage(
        "2026-10-17T16:25:00+02:00", None
    )


@pytest.mark.parametrize(
    ("until", "since", "exported"),
    [
        ("2026-01-01T00:00:00+00:00", None, None),
        ("2099-01-01T00:00:00+00:00", SINCE.isoformat(), "2099-01-01T00:00:00+00:00"),
    ],
)
def test_state_json_hides_an_expired_flag(
    bg_paths: Paths, until: str, since: str | None, exported: str | None
) -> None:
    bg_paths.claude_down.parent.mkdir(parents=True)
    flag = {"since": SINCE.isoformat(), "error": "x", "until": until}
    bg_paths.claude_down.write_text(json.dumps(flag), encoding="utf-8")
    doc = to_json(bg_paths, snapshot(bg_paths, today=SINCE.date()))
    assert (doc["claude_down_since"], doc["claude_down_until"]) == (since, exported)


def _claude_down(*_args: object, **_kwargs: object) -> dict[str, object]:
    msg = "usage limit reached"
    raise ClaudeUnavailableError(msg)


def test_a_local_grade_clears_the_flag(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The fallback answered: nothing is waiting on Claude any more."""
    _errlog.claude_failed(bg_paths, "usage limit reached")
    monkeypatch.setattr(_quiz, "ask", _claude_down)
    monkeypatch.setattr(_local, "ask_local", lambda *_a: {"passed": True})
    session = only_session(quiz_pair())
    _quiz.grade(make_book(), session, "x" * _quiz.MIN_SUMMARY_CHARS)
    assert _errlog.claude_outage(bg_paths) is None


def test_a_failed_local_grade_keeps_the_flag(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    _errlog.claude_failed(bg_paths, "usage limit reached")
    monkeypatch.setattr(_quiz, "ask", _claude_down)
    monkeypatch.setattr(_local, "ask_local", _claude_down)
    session = only_session(quiz_pair())
    with pytest.raises(ClaudeUnavailableError):
        _quiz.grade(make_book(), session, "x" * _quiz.MIN_SUMMARY_CHARS)
    assert _errlog.claude_outage(bg_paths) is not None


def test_a_bare_time_reads_in_the_failure_offset() -> None:
    """The default clock gives a fixed offset, not a named zone."""
    since = datetime(2026, 10, 17, 16, 25, tzinfo=timezone(timedelta(hours=2)))
    assert _errlog.reset_at("resets 4:40pm", since) == since.replace(minute=40)
