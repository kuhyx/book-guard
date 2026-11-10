# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Reply files carry a code and numbers, never a sentence for the app to paint.

The app shows a reply as an icon, a tint and a haptic; the old sentences
live only in the PC's log. This is the guard for that contract.
"""

from __future__ import annotations

import json
import re
from typing import TYPE_CHECKING

import pytest

from book_guard._app_handlers import HANDLERS
from book_guard._requests import CODES, Response, handle_requests

if TYPE_CHECKING:
    from book_guard._paths import Paths

_CODE = re.compile(r"^[a-z][a-z_]*$")


def test_a_sentence_is_not_a_code() -> None:
    with pytest.raises(ValueError, match="code"):
        Response(ok=False, code="That is not a 10- or 13-digit ISBN.")


def test_every_code_is_a_short_identifier() -> None:
    assert CODES
    assert all(_CODE.fullmatch(code) for code in CODES)


@pytest.mark.parametrize("kind", sorted(HANDLERS))
def test_a_refused_request_answers_with_a_code(bg_paths: Paths, kind: str) -> None:
    response = HANDLERS[kind](bg_paths, {})
    assert not response.ok or response.passed is not None
    assert response.code in CODES
    assert not hasattr(response, "message")


def test_the_reply_file_has_no_message(bg_paths: Paths) -> None:
    bg_paths.requests.mkdir(parents=True, exist_ok=True)
    request = {"id": "req-0002", "type": "register", "isbn": "12"}
    (bg_paths.requests / "req-0002.json").write_text(json.dumps(request))
    assert handle_requests(bg_paths, HANDLERS) == 1
    reply = json.loads((bg_paths.responses / "req-0002.json").read_text())
    assert reply == {"id": "req-0002", "ok": False, "code": "bad_isbn"}
