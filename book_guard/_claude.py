# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""One isolated Claude call: images and a prompt in, a JSON object out.

Uses the logged-in ``claude`` CLI (the Max subscription; the raw Messages API
needs a key this machine does not have). Isolation is the point of every flag:

* ``--setting-sources ""`` -- no user/project settings, so none of the hooks
  in ``~/.claude/settings.json`` run on a grading call;
* ``--tools ""`` and ``--strict-mcp-config`` -- the model can read nothing and
  call nothing; photos travel as base64 content blocks in the message itself;
* ``cwd=/`` -- no project ``CLAUDE.md`` to discover.

Checked 2026-09-26 with a canary token dropped into ``~/.claude/rules/``: the
call reported NONE and cost ~2k context tokens, i.e. none of the user's
instruction files were loaded. ``--bare`` would be cleaner but refuses the
subscription login.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
import re
import subprocess
from typing import Final

from book_guard import _errlog
from book_guard._constants import CLAUDE_TIMEOUT_SECONDS
from book_guard._paths import paths

_logger: Final = logging.getLogger(__name__)

CLAUDE_BIN: Final = Path.home() / ".local/bin/claude"
"""Absolute: a systemd user unit has no nvm/shell PATH."""

DEFAULT_MODEL: Final = "haiku"
"""Every call is Haiku unless the user names another model for one run
(``--model``). Deliberately not a config value: a stored default drifts."""

_FENCE: Final = re.compile(r"^```(?:json)?\s*|\s*```$")

TEXT_MARKER: Final = "---TEXT---"
"""Long free text (a page transcription) goes after this line, outside the
JSON: book prose is full of quotation marks, and Haiku regularly closes a
Polish „...” quote with a bare ASCII one, which breaks any JSON string."""


class ClaudeUnavailableError(RuntimeError):
    """The call could not produce a usable answer. Never "the answer is no"."""


def _message(prompt: str, images: list[str]) -> str:
    content: list[dict[str, object]] = [
        {
            "type": "image",
            "source": {"type": "base64", "media_type": "image/jpeg", "data": data},
        }
        for data in images
    ]
    content.append({"type": "text", "text": prompt})
    return json.dumps({"type": "user", "message": {"role": "user", "content": content}})


def _command(system: str, model: str) -> list[str]:
    return [
        str(CLAUDE_BIN),
        "-p",
        "--input-format",
        "stream-json",
        "--output-format",
        "stream-json",
        "--verbose",
        "--setting-sources",
        "",
        "--tools",
        "",
        "--strict-mcp-config",
        "--no-session-persistence",
        "--model",
        model,
        "--system-prompt",
        system,
    ]


def _results(stdout: str) -> list[dict[str, object]]:
    found: list[dict[str, object]] = []
    for line in stdout.splitlines():
        if not line.startswith("{") or '"type":"result"' not in line.replace(" ", ""):
            continue
        try:
            found.append(json.loads(line))  # starts with "{": always an object
        except ValueError:
            _logger.warning("skipping a cut-short result line: %.80s", line)
    return found


_WHY_TAIL: Final = 300


def why(stdout: str) -> str:
    """The CLI's own account of a failure: it prints it on stdout, not stderr.

    The last result event's text (e.g. a usage-limit notice) and API error
    status, else the tail of stdout, else "no output".
    """
    results = _results(stdout)
    if results:
        last = results[-1]
        parts = [str(last.get("result") or "").strip()]
        if last.get("api_error_status"):
            parts.append(f"(API status {last['api_error_status']})")
        text = " ".join(p for p in parts if p)
        if text:
            return text[:_WHY_TAIL]
    tail = stdout.strip()[-_WHY_TAIL:]
    return tail or "no output"


def parse_result(stdout: str) -> dict[str, object]:
    """The JSON object inside the stream's final ``result`` event.

    Raises:
        ClaudeUnavailableError: No result event, an error result, or a
            result that is not a JSON object.
    """
    results = _results(stdout)
    if not results or results[-1].get("is_error"):
        msg = f"claude returned no successful result: {why(stdout)}"
        raise ClaudeUnavailableError(msg)
    raw = str(results[-1].get("result", "")).strip()
    head, marker, body = raw.partition(TEXT_MARKER)
    text = _FENCE.sub("", head.strip())
    try:
        parsed = json.loads(text, strict=False)  # raw newlines inside long strings
    except ValueError as exc:
        msg = f"claude answered with non-JSON: {text[:200]!r}"
        raise ClaudeUnavailableError(msg) from exc
    if not isinstance(parsed, dict):
        msg = f"claude answered with a non-object: {text[:200]!r}"
        raise ClaudeUnavailableError(msg)
    if marker:
        parsed["text"] = _FENCE.sub("", body.strip())
    return parsed


_RETRY_NOTE: Final = (
    "\n\nIMPORTANT: your previous answer was not valid JSON. Answer with one "
    'JSON object only, escaping every double quote inside strings as \\".'
)


THINKING_TOKENS: Final = "1024"
"""Measured 2026-10-03: uncapped, Haiku spent 8,222 thinking tokens (75 s)
on a one-sentence grading verdict; at 1024 the same call took 11 s."""


def _ask_once(system: str, message: str, model: str) -> dict[str, object]:
    try:
        done = subprocess.run(
            _command(system, model),
            input=message + "\n",
            capture_output=True,
            text=True,
            cwd="/",
            env={**os.environ, "MAX_THINKING_TOKENS": THINKING_TOKENS},
            timeout=CLAUDE_TIMEOUT_SECONDS,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        msg = f"claude could not be run: {exc}"
        raise ClaudeUnavailableError(msg) from exc
    if done.returncode != 0:
        reason = why(done.stdout)
        _logger.warning(
            "claude exited %d: %s %s", done.returncode, reason, done.stderr[-400:]
        )
        msg = f"claude exited {done.returncode}: {reason}"
        raise ClaudeUnavailableError(msg)
    return parse_result(done.stdout)


def _ask(system: str, prompt: str, images: list[str], model: str) -> dict[str, object]:
    try:
        return _ask_once(system, _message(prompt, images), model)
    except ClaudeUnavailableError as exc:
        if "non-JSON" not in str(exc) and "non-object" not in str(exc):
            raise
        _logger.warning("retrying after malformed JSON: %s", exc)
    return _ask_once(system, _message(prompt + _RETRY_NOTE, images), model)


def ask(
    system: str,
    prompt: str,
    images: list[str] | None = None,
    *,
    model: str = DEFAULT_MODEL,
) -> dict[str, object]:
    """Run one isolated call and return its JSON answer.

    One retry, and only for malformed JSON: book text is full of quotation
    marks, and a model that forgets to escape one is a formatting slip, not
    an outage. Every failure lands in ``errors.jsonl`` with the CLI's own
    reason, and marks the outage until the next call goes through.

    Raises:
        ClaudeUnavailableError: The CLI is missing, timed out, failed, or
            answered twice with something that is not a JSON object.
    """
    active = paths()
    try:
        answer = _ask(system, prompt, images or [], model)
    except ClaudeUnavailableError as exc:
        _errlog.claude_failed(active, str(exc))
        raise
    _errlog.claude_ok(active)
    return answer
