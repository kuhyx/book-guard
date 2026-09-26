# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_claude (fake subprocess.run) and _vision (fake ask)."""

from __future__ import annotations

import json
import subprocess
from typing import Any

import pytest

from book_guard import _claude, _vision
from book_guard._claude import ClaudeUnavailableError
from book_guard._constants import CLAUDE_TIMEOUT_SECONDS


def _result(result: str, *, is_error: bool = False) -> str:
    return json.dumps({"type": "result", "result": result, "is_error": is_error})


def _stream(*results: str) -> str:
    lines = ["not json", '{"type":"system","subtype":"init"}', *results]
    return "\n".join(lines) + "\n"


class FakeRun:
    """Records every call; answers from a queue of (returncode, stdout)."""

    def __init__(self, *answers: tuple[int, str] | BaseException) -> None:
        self.answers = list(answers)
        self.calls: list[tuple[list[str], dict[str, object]]] = []

    def __call__(
        self, command: list[str], **kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        self.calls.append((command, kwargs))
        answer = self.answers.pop(0)
        if isinstance(answer, BaseException):
            raise answer
        code, stdout = answer
        return subprocess.CompletedProcess(command, code, stdout, "boom " * 200)

    def message(self, index: int) -> dict[str, Any]:
        raw = self.calls[index][1]["input"]
        assert isinstance(raw, str)
        parsed: dict[str, Any] = json.loads(raw)
        return parsed


def _install(monkeypatch: pytest.MonkeyPatch, fake: FakeRun) -> FakeRun:
    monkeypatch.setattr(subprocess, "run", fake)
    return fake


def test_ask_success_with_fence_and_images(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = _install(
        monkeypatch, FakeRun((0, _stream(_result('```json\n{"a": 1}\n```'))))
    )
    assert _claude.ask("sys", "prompt", ["IMG1", "IMG2"], model="opus") == {"a": 1}
    command, kwargs = fake.calls[0]
    assert command[0] == str(_claude.CLAUDE_BIN)
    assert command[command.index("--model") + 1] == "opus"
    assert command[command.index("--system-prompt") + 1] == "sys"
    assert kwargs["cwd"] == "/"
    assert kwargs["timeout"] == CLAUDE_TIMEOUT_SECONDS
    content = fake.message(0)["message"]["content"]
    assert [c["type"] for c in content] == ["image", "image", "text"]
    assert content[0]["source"]["data"] == "IMG1"
    assert content[-1]["text"] == "prompt"


def test_ask_without_images(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = _install(monkeypatch, FakeRun((0, _stream(_result('{"ok": true}')))))
    assert _claude.ask("s", "p") == {"ok": True}
    command = fake.calls[0][0]
    assert command[command.index("--model") + 1] == _claude.DEFAULT_MODEL


def test_text_marker_goes_into_text() -> None:
    raw = '{"kind": "page"}\n---TEXT---\n```\nShe said "hi".\nLine two\n```'
    parsed = _claude.parse_result(_stream(_result(raw)))
    assert parsed == {"kind": "page", "text": 'She said "hi".\nLine two'}


def test_last_result_wins_and_raw_newlines_allowed() -> None:
    stdout = _stream(_result('{"n": 1}'), _result('{"t": "a\nb"}'))
    assert _claude.parse_result(stdout) == {"t": "a\nb"}


@pytest.mark.parametrize(
    "stdout",
    [_stream(), _stream(_result('{"a": 1}', is_error=True)), ""],
)
def test_no_successful_result(stdout: str) -> None:
    with pytest.raises(ClaudeUnavailableError, match="no successful result"):
        _claude.parse_result(stdout)


def test_non_json_retries_once_then_succeeds(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = _install(
        monkeypatch,
        FakeRun((0, _stream(_result("sorry, no"))), (0, _stream(_result('{"x": 2}')))),
    )
    assert _claude.ask("s", "p") == {"x": 2}
    assert len(fake.calls) == 2
    retry_text = fake.message(1)["message"]["content"][-1]["text"]
    assert "previous answer was not valid JSON" in retry_text


def test_non_object_retries_then_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = _install(
        monkeypatch,
        FakeRun((0, _stream(_result("[1, 2]"))), (0, _stream(_result("[3]")))),
    )
    with pytest.raises(ClaudeUnavailableError, match="non-object"):
        _claude.ask("s", "p")
    assert len(fake.calls) == 2


def test_non_json_twice_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(
        monkeypatch, FakeRun((0, _stream(_result("{"))), (0, _stream(_result("x"))))
    )
    with pytest.raises(ClaudeUnavailableError, match="non-JSON"):
        _claude.ask("s", "p")


def test_nonzero_exit_is_not_retried(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = _install(monkeypatch, FakeRun((2, "")))
    with pytest.raises(ClaudeUnavailableError, match="exited 2"):
        _claude.ask("s", "p")
    assert len(fake.calls) == 1


def test_is_error_is_not_retried(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = _install(monkeypatch, FakeRun((0, _stream(_result("{}", is_error=True)))))
    with pytest.raises(ClaudeUnavailableError, match="no successful result"):
        _claude.ask("s", "p")
    assert len(fake.calls) == 1


@pytest.mark.parametrize(
    "error",
    [FileNotFoundError("no claude"), subprocess.TimeoutExpired("claude", 240)],
)
def test_cannot_run(monkeypatch: pytest.MonkeyPatch, error: BaseException) -> None:
    _install(monkeypatch, FakeRun(error))
    with pytest.raises(ClaudeUnavailableError, match="could not be run"):
        _claude.ask("s", "p")


@pytest.mark.parametrize(
    ("answer", "expected"),
    [
        ({"kind": "page", "page_number": 12, "text": "abc"}, ("page", 12, None, "abc")),
        ({"kind": "page", "page_number": "7"}, ("page", 7, None, "")),
        ({"kind": "page", "page_number": True}, ("other", None, None, "")),
        ({"kind": "page", "page_number": "xii"}, ("other", None, None, "")),
        ({"kind": "page", "page_number": 0}, ("other", None, None, "")),
        ({"kind": "page", "page_number": 3.0}, ("other", None, None, "")),
        ({"kind": "page"}, ("other", None, None, "")),
        (
            {"kind": "isbn", "isbn": "978-83-240-1234-5"},
            ("isbn", None, "9788324012345", ""),
        ),
        ({"kind": "isbn", "isbn": "0-306-40615-x"}, ("isbn", None, "030640615X", "")),
        ({"kind": "isbn", "isbn": "12345"}, ("other", None, None, "")),
        ({"kind": "isbn", "isbn": None}, ("other", None, None, "")),
        ({"kind": "cat", "page_number": 4, "text": None}, ("other", None, None, "")),
        ({}, ("other", None, None, "")),
        ({"kind": "other", "isbn": "9788324012345"}, ("other", None, None, "")),
    ],
)
def test_from_answer(answer: dict[str, object], expected: tuple[object, ...]) -> None:
    reading = _vision.from_answer(answer)
    assert (reading.kind, reading.page_number, reading.isbn, reading.text) == expected


def test_read_photo(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[tuple[object, ...]] = []

    def fake_ask(
        system: str, prompt: str, images: list[str], *, model: str
    ) -> dict[str, object]:
        calls.append((system, prompt, images, model))
        return {"kind": "page", "page_number": 5, "text": "words"}

    monkeypatch.setattr(_vision, "ask", fake_ask)
    reading = _vision.read_photo("B64", model="sonnet")
    assert reading == _vision.Reading("page", 5, None, "words")
    assert calls[0][2] == ["B64"]
    assert calls[0][3] == "sonnet"
    assert "---TEXT---" in str(calls[0][1])


def test_read_photo_propagates_unavailable(monkeypatch: pytest.MonkeyPatch) -> None:
    def broken(*_a: object, **_k: object) -> dict[str, object]:
        msg = "down"
        raise ClaudeUnavailableError(msg)

    monkeypatch.setattr(_vision, "ask", broken)
    with pytest.raises(ClaudeUnavailableError):
        _vision.read_photo("B64")
