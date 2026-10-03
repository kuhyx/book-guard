# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_photo_context: what a photo was taken for, and the phone's sidecar."""

from __future__ import annotations

from datetime import timedelta
from typing import TYPE_CHECKING

import pytest

from book_guard import _ledger
from book_guard._pagenum import Context
from book_guard._photo_context import (
    Sidecar,
    context_for,
    parse_box,
    read_sidecar,
    sidecar_path,
)
from book_guard._sessions import check_page_for
from book_guard.tests._flow_helpers import T0, add_book, rec

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths


def test_sidecar_path(tmp_path: Path) -> None:
    assert sidecar_path(tmp_path / "a.jpg") == tmp_path / "a.jpg.json"


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ('{"page": 51, "box": [1, 2, 3, 4]}', Sidecar(51, (1, 2, 3, 4))),
        ('{"page": true, "box": [1, 2, 3]}', Sidecar()),
        ('{"page": "51", "box": [1, 2, 3, "4"]}', Sidecar()),
        ('{"box": [5, 5, 5, 9]}', Sidecar()),
        ('{"box": [1, 2, 3, true]}', Sidecar()),
        ("[1]", Sidecar()),
        ("not json", Sidecar()),
    ],
)
def test_read_sidecar(tmp_path: Path, raw: str, expected: Sidecar) -> None:
    photo = tmp_path / "a.jpg"
    sidecar_path(photo).write_text(raw, encoding="utf-8")
    assert read_sidecar(photo) == expected


def test_no_sidecar(tmp_path: Path) -> None:
    assert read_sidecar(tmp_path / "a.jpg") == Sidecar()


def test_parse_box_rejects_non_lists() -> None:
    assert parse_box("1,2,3,4") is None


def test_contexts(bg_paths: Paths) -> None:
    add_book(bg_paths, pages=406)
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    later = T0 + timedelta(hours=3)
    start, end = rec("s", 7, T0), rec("e", 51, T0 + timedelta(minutes=45))
    check = check_page_for(start, end)
    assert check is not None
    # The check photo comes after the stop photo: "near" must skip it.
    records = {
        r.sha: r for r in (start, end, rec("c", check, T0 + timedelta(minutes=50)))
    }
    assert context_for("start_x.jpg", later, records, ledger) == Context(
        near=51, last_page=406
    )
    assert context_for(f"check{check}_x.jpg", later, records, ledger) == Context(
        expected=check, last_page=406
    )
    assert context_for("stop_x.jpg", later, records, ledger) == Context(
        after=None, last_page=406
    )
    assert context_for("IMG_1.jpg", later, records, ledger) == Context(last_page=406)
    open_start = {**records, "o": rec("o", 60, T0 + timedelta(hours=2))}
    assert context_for("stop_x.jpg", later, open_start, ledger).after == 60


def test_context_without_a_book(bg_paths: Paths) -> None:
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert context_for("start_x.jpg", T0, {}, ledger) == Context()
