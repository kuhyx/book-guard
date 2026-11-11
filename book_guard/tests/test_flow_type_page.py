# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The app's ``type_page`` request: a page number typed for a photo with none."""

from __future__ import annotations

from dataclasses import replace
import json
from typing import TYPE_CHECKING

import pytest

from book_guard import _photos, _quiz, _reread
from book_guard._app_handlers import HANDLERS
from book_guard._photos import OK, REJECTED
from book_guard._quiz import Verdict
from book_guard._requests import Response, handle_requests
from book_guard._vision import OTHER, PAGE, Reading
from book_guard.tests._flow_helpers import (
    T0,
    make_book,
    only_session,
    quiz_pair,
    rec,
    seed_photos,
)

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

    from book_guard._pagenum import Box, Context
    from book_guard._paths import Paths


def _chapter_opener(paths: Paths, *, kind: str = OTHER, status: str = REJECTED) -> str:
    record = rec("start_a", None, T0, kind=kind, status=status)
    seed_photos(paths, record)
    paths.processed.mkdir(parents=True, exist_ok=True)
    (paths.processed / f"{record.sha[:12]}-{record.name}").write_bytes(b"jpeg")
    return record.name


def _reader(
    hints: list[int | None], text: str = "words"
) -> Callable[[Path, Context, Box | None], Reading]:
    def read(_path: Path, context: Context, _box: Box | None = None) -> Reading:
        hints.append(context.hint)
        return Reading(PAGE, context.hint, None, text)

    return read


@pytest.mark.parametrize(
    "request_body",
    [
        {},
        {"photo": "start_a.jpg"},
        {"page": 1},
        {"photo": 5, "page": 1},
        {"photo": "start_a.jpg", "page": True},
        {"photo": "start_a.jpg", "page": "1"},
        {"photo": "start_a.jpg", "page": 0},
        {"photo": "start_a.jpg", "page": -3},
        {"photo": "start_a.jpg", "page": 10000},
    ],
)
def test_bad_requests(bg_paths: Paths, request_body: dict[str, object]) -> None:
    response = _reread.type_page(bg_paths, request_body)
    assert response == Response(ok=False, code="bad_page")


def test_unknown_photo_or_no_capture_time(bg_paths: Paths) -> None:
    name = _chapter_opener(bg_paths)
    assert _reread.type_page(bg_paths, {"photo": "nope.jpg", "page": 1}) == Response(
        ok=False, code="no_photo"
    )
    (record,) = _photos.load(bg_paths.photos).values()
    seed_photos(bg_paths, replace(record, taken_at=""))
    assert _reread.type_page(bg_paths, {"photo": name, "page": 1}).code == "no_photo"


def test_a_read_number_is_never_overridden(bg_paths: Paths) -> None:
    seed_photos(bg_paths, rec("start_b", 51, T0))
    response = _reread.type_page(bg_paths, {"photo": "start_b.jpg", "page": 3})
    assert response == Response(ok=False, code="already_read", data={"page": 51})
    (record,) = _photos.load(bg_paths.photos).values()
    assert (record.page, record.page_source) == (51, "")


@pytest.mark.parametrize("kind", ["isbn", "toc", "ebook"])
def test_only_page_or_other_photos(bg_paths: Paths, kind: str) -> None:
    name = _chapter_opener(bg_paths, kind=kind, status=OK)
    assert _reread.type_page(bg_paths, {"photo": name, "page": 1}).code == "refused"


def test_filed_photo_gone(bg_paths: Paths) -> None:
    name = _chapter_opener(bg_paths)
    for path in bg_paths.processed.iterdir():
        path.unlink()
    response = _reread.type_page(bg_paths, {"photo": name, "page": 1})
    assert response == Response(ok=False, code="photo_gone")


def test_typed_page_is_trusted_and_recorded_as_typed(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    name = _chapter_opener(bg_paths)
    hints: list[int | None] = []
    monkeypatch.setattr(_reread, "read", _reader(hints))
    response = _reread.type_page(bg_paths, {"photo": name, "page": 1})
    assert response == Response(ok=True, code="read", data={"page": 1})
    assert hints == [1]  # the phone's channel: the page is the reader's hint
    (record,) = _photos.load(bg_paths.photos).values()
    assert (record.kind, record.page, record.status, record.reason) == (PAGE, 1, OK, "")
    assert (record.page_source, record.text) == ("typed", "words")


def test_typed_page_keeps_the_old_text_when_nothing_is_transcribed(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    name = _chapter_opener(bg_paths)
    (record,) = _photos.load(bg_paths.photos).values()
    seed_photos(bg_paths, replace(record, text="old"))
    monkeypatch.setattr(_reread, "read", _reader([], text=""))
    assert _reread.type_page(bg_paths, {"photo": name, "page": 1}).ok
    (record,) = _photos.load(bg_paths.photos).values()
    assert record.text == "old"


def test_the_handler_is_registered_and_answers_over_the_request_channel(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    assert HANDLERS["type_page"] is _reread.type_page
    name = _chapter_opener(bg_paths)
    monkeypatch.setattr(_reread, "read", _reader([]))
    bg_paths.requests.mkdir(parents=True, exist_ok=True)
    body = {"id": "req-type-1", "type": "type_page", "photo": name, "page": 1}
    (bg_paths.requests / "req-type-1.json").write_text(json.dumps(body))
    assert handle_requests(bg_paths, HANDLERS) == 1
    reply = json.loads((bg_paths.responses / "req-type-1.json").read_text())
    assert (reply["ok"], reply["code"]) == (True, "read")


def test_old_caches_load_with_no_source(bg_paths: Paths) -> None:
    record = rec("start_a", 3, T0)
    seed_photos(bg_paths, record)
    raw = json.loads(bg_paths.photos.read_text())
    del raw[record.sha]["page_source"]
    bg_paths.photos.write_text(json.dumps(raw))
    assert _photos.load(bg_paths.photos)[record.sha].page_source == ""


def test_a_credit_using_a_typed_page_says_so(bg_paths: Paths) -> None:
    start, end = quiz_pair()
    session = only_session([replace(start, page_source="typed"), end])
    entry = _quiz.record_verdict(
        bg_paths, make_book(), session, Verdict(True, "f"), "s"
    )
    assert entry is not None
    assert entry.detail["page_source"] == "typed"
    assert entry.detail["typed_photos"] == "start"


def test_a_credit_from_read_pages_has_no_page_source(bg_paths: Paths) -> None:
    session = only_session(quiz_pair())
    entry = _quiz.record_verdict(
        bg_paths, make_book(), session, Verdict(True, "f"), "s"
    )
    assert entry is not None
    assert "page_source" not in entry.detail
    assert "typed_photos" not in entry.detail
