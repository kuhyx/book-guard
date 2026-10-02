# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_http: an answer, a 404, and a refusal are three different outcomes."""

from __future__ import annotations

from email.message import Message
import io
from typing import Self
from urllib.error import HTTPError, URLError

import pytest

from book_guard import _http


class _Body:
    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_exc: object) -> None:
        return None

    def read(self) -> bytes:
        return b"hi"


def _raise(exc: BaseException) -> object:
    def opener(*_args: object, **_kwargs: object) -> object:
        raise exc

    return opener


def _status(code: int) -> HTTPError:
    return HTTPError("https://x.org/a", code, "err", Message(), io.BytesIO())


def test_answer(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(_http, "urlopen", lambda _req, timeout: _Body())
    assert _http.get("x.org", "/a") == b"hi"


def test_not_found_is_an_answer(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(_http, "urlopen", _raise(_status(404)))
    assert _http.get("x.org", "/a") is None


@pytest.mark.parametrize(
    ("error", "said"),
    [
        (_status(429), "x.org answered 429"),
        (URLError("no route"), "x.org unreachable"),
        (TimeoutError("slow"), "x.org unreachable (slow)"),
    ],
)
def test_refusals(monkeypatch: pytest.MonkeyPatch, error: Exception, said: str) -> None:
    monkeypatch.setattr(_http, "urlopen", _raise(error))
    with pytest.raises(
        _http.UnavailableError, match=said.replace("(", r"\(").replace(")", r"\)")
    ):
        _http.get("x.org", "/a")
