# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The app's ``box`` request: re-reading a filed photo inside a drawn box."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

from book_guard import _photos, _reread
from book_guard._photos import OK, REJECTED
from book_guard._vision import OTHER, PAGE, Reading
from book_guard.tests._flow_helpers import T0, rec, seed_photos

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._pagenum import Box, Context
    from book_guard._paths import Paths

_BOX = [10, 20, 30, 40]


def _rejected(paths: Paths, *, taken: bool = True) -> str:
    record = rec("start_a", None, T0, kind=OTHER, status=REJECTED)
    if not taken:
        record = _photos.PhotoRecord(**{**record.__dict__, "taken_at": ""})
    seed_photos(paths, record)
    paths.processed.mkdir(parents=True, exist_ok=True)
    (paths.processed / f"{record.sha[:12]}-{record.name}").write_bytes(b"jpeg")
    return record.name


def _reader(reading: Reading, seen: list[Box | None]) -> object:
    def read(_path: Path, _context: Context, box: Box | None) -> Reading:
        seen.append(box)
        return reading

    return read


@pytest.mark.parametrize(
    ("request_body", "message"),
    [
        ({"photo": "a.jpg"}, "Draw a box around the page number first."),
        ({"box": _BOX}, "Draw a box around the page number first."),
        ({"photo": "nope.jpg", "box": _BOX}, "No readable photo named nope.jpg."),
    ],
)
def test_bad_requests(
    bg_paths: Paths, request_body: dict[str, object], message: str
) -> None:
    response = _reread.box_photo(bg_paths, request_body)
    assert (response.ok, response.message) == (False, message)


def test_photo_without_capture_time(bg_paths: Paths) -> None:
    name = _rejected(bg_paths, taken=False)
    response = _reread.box_photo(bg_paths, {"photo": name, "box": _BOX})
    assert response.message == f"No readable photo named {name}."


def test_an_accepted_page_is_left_alone(bg_paths: Paths) -> None:
    seed_photos(bg_paths, rec("start_b", 51, T0))
    response = _reread.box_photo(bg_paths, {"photo": "start_b.jpg", "box": _BOX})
    assert (response.ok, response.message) == (False, "Already read as p. 51.")


def test_filed_photo_gone(bg_paths: Paths) -> None:
    name = _rejected(bg_paths)
    for path in bg_paths.processed.iterdir():
        path.unlink()
    response = _reread.box_photo(bg_paths, {"photo": name, "box": _BOX})
    assert response.message == f"{name} is no longer on the PC."


def test_box_turns_a_rejection_into_a_page(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    name = _rejected(bg_paths)
    seen: list[Box | None] = []
    monkeypatch.setattr(
        _reread, "read", _reader(Reading(PAGE, 7, None, "words", rotation=90), seen)
    )
    response = _reread.box_photo(bg_paths, {"photo": name, "box": _BOX})
    assert (response.ok, response.message) == (True, "Read as p. 7.")
    assert seen == [(10, 20, 30, 40)]
    (record,) = _photos.load(bg_paths.photos).values()
    assert (record.kind, record.page, record.status) == (PAGE, 7, OK)


def test_box_still_unreadable(bg_paths: Paths, monkeypatch: pytest.MonkeyPatch) -> None:
    name = _rejected(bg_paths)
    monkeypatch.setattr(
        _reread,
        "read",
        _reader(Reading(OTHER, None, None, "", reason="no page number found"), []),
    )
    response = _reread.box_photo(bg_paths, {"photo": name, "box": _BOX})
    assert response.message == "Still no page number: no page number found"
    (record,) = _photos.load(bg_paths.photos).values()
    assert (record.status, record.reason) == (REJECTED, "no page number found")


def test_the_phones_page_in_a_box_request_is_the_hint(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    name = _rejected(bg_paths)
    hints: list[int | None] = []

    def read(_path: Path, context: Context, _box: Box | None) -> Reading:
        hints.append(context.hint)
        return Reading(PAGE, 51, None, "words")

    monkeypatch.setattr(_reread, "read", read)
    request: dict[str, object] = {"photo": name, "box": _BOX, "page": 51}
    assert _reread.box_photo(bg_paths, request).message == "Read as p. 51."
    assert hints == [51]


@pytest.mark.parametrize("page", [None, True, "51", 51.0])
def test_a_box_request_without_a_proper_page_has_no_hint(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch, page: object
) -> None:
    name = _rejected(bg_paths)
    hints: list[int | None] = []

    def read(_path: Path, context: Context, _box: Box | None) -> Reading:
        hints.append(context.hint)
        return Reading(OTHER, None, None, "", reason="no page number found")

    monkeypatch.setattr(_reread, "read", read)
    request: dict[str, object] = {"photo": name, "box": _BOX}
    if page is not None:
        request["page"] = page
    _reread.box_photo(bg_paths, request)
    assert hints == [None]
