# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""One GET helper for the metadata sources, telling three outcomes apart.

* bytes -- the service answered;
* ``None`` -- it answered "no such thing" (404);
* :class:`UnavailableError` -- it did not answer: rate limit, server error,
  timeout, no network. Only this kind of failure may be retried later; a
  404 is an answer and can be cached.
"""

from __future__ import annotations

from http import HTTPStatus
from typing import Final
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

TIMEOUT: Final = 15
HEADERS: Final = {"User-Agent": "book-guard/1.0 (github.com/kuhyx/book-guard)"}


class UnavailableError(OSError):
    """The source did not answer (as opposed to answering "not found")."""


def get(host: str, path: str) -> bytes | None:
    """GET ``https://{host}{path}``; ``None`` on 404.

    HTTPS only, by construction: no caller can hand urllib a ``file:`` URL.

    Raises:
        UnavailableError: Rate limited, server error, timeout or no network.
    """
    try:
        with urlopen(
            Request(f"https://{host}{path}", headers=HEADERS), timeout=TIMEOUT
        ) as response:
            body: bytes = response.read()
            return body
    except HTTPError as exc:
        # An HTTPError holds the error response open; close it first.
        exc.close()
        if exc.code == HTTPStatus.NOT_FOUND:
            return None
        msg = f"{host} answered {exc.code}"
        raise UnavailableError(msg) from exc
    except (URLError, TimeoutError) as exc:
        msg = f"{host} unreachable ({exc})"
        raise UnavailableError(msg) from exc
