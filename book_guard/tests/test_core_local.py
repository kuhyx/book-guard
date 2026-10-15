# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_local: the ollama fallback for when Claude cannot answer."""

from __future__ import annotations

import io
import json
from typing import TYPE_CHECKING
from urllib.error import URLError

import pytest

from book_guard import _local
from book_guard._claude import RETRY_NOTE, ClaudeUnavailableError
from book_guard._local import LocalUnavailableError

if TYPE_CHECKING:
    from urllib.request import Request


def _serve(
    monkeypatch: pytest.MonkeyPatch, *replies: object
) -> list[dict[str, object]]:
    """Answer each ollama request with the next reply; return the requests."""
    sent: list[dict[str, object]] = []
    queue = list(replies)

    def urlopen(request: Request, timeout: float) -> io.BytesIO:
        assert timeout == _local.LOCAL_TIMEOUT_SECONDS
        assert request.full_url == f"http://{_local.OLLAMA_HOST}/api/chat"
        assert isinstance(request.data, bytes)
        sent.append(json.loads(request.data))
        reply = queue.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return io.BytesIO(json.dumps(reply).encode())

    monkeypatch.setattr(_local, "urlopen", urlopen)
    return sent


def _content(text: str) -> dict[str, object]:
    return {"message": {"role": "assistant", "content": text}}


def test_num_ctx_holds_the_prompt_and_rounds_up() -> None:
    assert _local.num_ctx("x") == _local.MIN_CTX
    big = "x" * 60_000  # 20k tokens + 1k answer -> 24576
    assert _local.num_ctx(big) == 24_576
    assert _local.num_ctx(big, images=1) == 24_576 + _local.IMAGE_TOKENS


def test_a_text_call_goes_to_the_grader_model(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    sent = _serve(monkeypatch, _content('```json\n{"passed": true},\n```'))
    assert _local.ask_local("SYS", "PROMPT") == {"passed": True}
    (payload,) = sent
    assert payload["model"] == _local.LOCAL_MODEL
    assert payload["stream"] is False
    assert payload["think"] is False
    assert payload["options"] == {"num_ctx": _local.MIN_CTX}
    assert payload["messages"] == [
        {"role": "system", "content": "SYS"},
        {"role": "user", "content": "PROMPT"},
    ]


def test_a_photo_goes_to_the_vision_model_with_its_text(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    sent = _serve(monkeypatch, _content('{"kind": "toc"}\n---TEXT---\nWstęp 7'))
    answer = _local.ask_local("SYS", "PROMPT", ["B64"])
    assert answer == {"kind": "toc", "text": "Wstęp 7"}
    assert sent[0]["model"] == _local.LOCAL_VISION_MODEL
    messages = sent[0]["messages"]
    assert isinstance(messages, list)
    assert messages[1]["images"] == ["B64"]


def test_malformed_json_is_retried_once(monkeypatch: pytest.MonkeyPatch) -> None:
    sent = _serve(monkeypatch, _content("nope"), _content('{"passed": false}'))
    assert _local.ask_local("SYS", "PROMPT") == {"passed": False}
    second = sent[1]["messages"]
    assert isinstance(second, list)
    assert second[1]["content"] == "PROMPT" + RETRY_NOTE


def test_malformed_json_twice_is_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _serve(monkeypatch, _content("nope"), _content("[1]"))
    with pytest.raises(LocalUnavailableError, match="non-object"):
        _local.ask_local("SYS", "PROMPT")


@pytest.mark.parametrize(
    "reply",
    [URLError("refused"), TimeoutError("slow"), {"error": "no model"}, ["x"]],
)
def test_ollama_down_is_not_retried(
    monkeypatch: pytest.MonkeyPatch, reply: object
) -> None:
    sent = _serve(monkeypatch, reply)
    with pytest.raises(LocalUnavailableError, match="local model unavailable"):
        _local.ask_local("SYS", "PROMPT")
    assert len(sent) == 1


def test_local_unavailable_is_a_claude_outage_to_every_caller() -> None:
    assert issubclass(LocalUnavailableError, ClaudeUnavailableError)
