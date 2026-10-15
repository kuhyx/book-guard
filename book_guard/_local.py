# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The fallback model: the same call as :func:`book_guard._claude.ask`, on ollama.

Used only after Claude failed (outage, usage cap): a summary graded by a
local model beats one credited ungraded after :data:`GRADER_GRACE`.

Two models, measured 2026-10-15 on the reader's 15 real summaries
(``scripts/replay_verdicts.py``; Haiku passes all 15): the dense
``qwen3:32b`` grades (14 of 15 agree), while both 3B-active MoE models
failed 4 genuine summaries *for* going past the photos. A contents page
only needs transcribing, so the fast vision MoE reads it; the swap costs a
reload, about once per book. Deliberately constants, like ``DEFAULT_MODEL``:
a stored default drifts.
"""

from __future__ import annotations

import json
import logging
from typing import Final
from urllib.error import URLError
from urllib.request import Request, urlopen

from book_guard._claude import RETRY_NOTE, ClaudeUnavailableError, parse_answer

_logger: Final = logging.getLogger(__name__)

LOCAL_MODEL: Final = "qwen3:32b"
"""The fallback grader (text only; the grader never sees photos)."""
LOCAL_VISION_MODEL: Final = "qwen3-vl:30b-a3b-instruct"
"""The fallback reader of a photographed table of contents."""
OLLAMA_HOST: Final = "127.0.0.1:11434"
LOCAL_TIMEOUT_SECONDS: Final = 180
"""A cold start loads ~20 GB first (measured 2026-10-15: ~25 s); a warm
vote on a real summary took ~5-10 s. Kept so a Claude timeout plus three
local votes (240 + 3 x 180 s) stays inside the inbox unit's 15 min."""

MIN_CTX: Final = 8192
CTX_STEP: Final = 4096
CHARS_PER_TOKEN: Final = 3
"""Conservative for Polish prose (it tokenizes nearer 3.5 chars a token)."""
ANSWER_TOKENS: Final = 1024
IMAGE_TOKENS: Final = 4096
"""A photo's share of the window (qwen-vl caps a large one near this)."""


def num_ctx(text: str, images: int = 0) -> int:
    """A context window that holds ``text`` and the answer, never fewer.

    ollama silently truncates a prompt past its window (default 4k) and still
    answers -- a grader judging half a book span. A span runs to 150k chars,
    so the window is sized per prompt; past the card's VRAM ollama spills to
    the CPU, slower but whole. Rounded up so the votes on one prompt share a
    load.
    """
    need = len(text) // CHARS_PER_TOKEN + images * IMAGE_TOKENS + ANSWER_TOKENS
    return max(MIN_CTX, -(-need // CTX_STEP) * CTX_STEP)


class LocalUnavailableError(ClaudeUnavailableError):
    """Neither Claude nor the local model answered.

    A subclass, so every caller that waits out a Claude outage waits this
    one out the same way.
    """


def _payload(system: str, prompt: str, images: list[str]) -> bytes:
    model = LOCAL_VISION_MODEL if images else LOCAL_MODEL
    user: dict[str, object] = {"role": "user", "content": prompt}
    if images:
        user["images"] = images
    return json.dumps(
        {
            "model": model,
            "stream": False,
            "think": False,  # qwen3:32b thinks by default: minutes per vote
            "messages": [{"role": "system", "content": system}, user],
            "options": {"num_ctx": num_ctx(system + prompt, len(images))},
        }
    ).encode()


def _ask_once(system: str, prompt: str, images: list[str]) -> dict[str, object]:
    try:
        with urlopen(
            Request(
                f"http://{OLLAMA_HOST}/api/chat",
                data=_payload(system, prompt, images),
                headers={"Content-Type": "application/json"},
            ),
            timeout=LOCAL_TIMEOUT_SECONDS,
        ) as response:
            reply = json.loads(response.read())
        content = str(reply["message"]["content"])
    except (URLError, TimeoutError, OSError, ValueError, KeyError, TypeError) as exc:
        msg = f"local model unavailable: {exc}"
        raise LocalUnavailableError(msg) from exc
    try:
        return parse_answer(content, LOCAL_MODEL)
    except ClaudeUnavailableError as exc:
        raise LocalUnavailableError(str(exc)) from exc


def ask_local(
    system: str, prompt: str, images: list[str] | None = None
) -> dict[str, object]:
    """One call to the local model; its JSON answer.

    One retry, and only for malformed JSON -- as :func:`book_guard._claude.ask`.

    Raises:
        LocalUnavailableError: ollama is down, timed out, or twice did not
            answer with a JSON object.
    """
    try:
        return _ask_once(system, prompt, images or [])
    except LocalUnavailableError as exc:
        if "non-JSON" not in str(exc) and "non-object" not in str(exc):
            raise
        _logger.warning("retrying the local model after malformed JSON: %s", exc)
    return _ask_once(system, prompt + RETRY_NOTE, images or [])
