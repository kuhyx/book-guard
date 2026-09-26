# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_ledger: signing, verification, corrupt files and append semantics."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

from gatelock.log_integrity import compute_entry_hmac
import pytest

from book_guard import _ledger
from book_guard._errors import CorruptFileError
from book_guard._ledger import BOOK, CREDIT, ESCAPE, REJECT, Entry, Ledger

if TYPE_CHECKING:
    from pathlib import Path

    from book_guard._paths import Paths


def _signed(row: dict[str, object], key_file: Path) -> dict[str, object]:
    signature = compute_entry_hmac(row, key_file=key_file)
    assert signature is not None
    return {**row, "hmac": signature}


def _write_rows(path: Path, rows: list[object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"version": 1, "entries": rows}), encoding="utf-8")


def test_kinds_are_distinct() -> None:
    assert len({BOOK, CREDIT, REJECT, ESCAPE}) == 4


def test_key_usable(bg_paths: Paths, tmp_path: Path) -> None:
    assert _ledger.key_usable(bg_paths.key_file)
    assert not _ledger.key_usable(tmp_path / "missing.key")


def test_load_missing_is_empty(bg_paths: Paths) -> None:
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert ledger.entries == []


@pytest.mark.parametrize("content", ["[]", '{"entries": 5}', '{"version": 1}'])
def test_load_corrupt_raises(bg_paths: Paths, content: str) -> None:
    bg_paths.ledger.parent.mkdir(parents=True)
    bg_paths.ledger.write_text(content, encoding="utf-8")
    with pytest.raises(CorruptFileError, match="no entries array"):
        _ledger.load(bg_paths.ledger, bg_paths.key_file)


def test_append_and_load_roundtrip(bg_paths: Paths) -> None:
    entry = Entry(
        entry_id="credit:1",
        kind=CREDIT,
        day="2026-10-02",
        amount=12,
        detail={"isbn": "123", "end_page": "40"},
    )
    assert _ledger.append(bg_paths.ledger, bg_paths.key_file, entry)
    assert not _ledger.append(bg_paths.ledger, bg_paths.key_file, entry)
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert len(ledger.entries) == 1
    stored = ledger.entries[0]
    assert stored.amount == 12
    assert stored.detail == {"isbn": "123", "end_page": "40"}
    assert stored.created_at  # stamped on append
    assert ledger.has("credit:1")
    assert not ledger.has("credit:2")
    assert ledger.of_kind(CREDIT) == [stored]
    assert ledger.of_kind(BOOK) == []


def test_append_keeps_given_created_at(bg_paths: Paths) -> None:
    entry = Entry(entry_id="e", kind=ESCAPE, day="d", created_at="2026-10-01T00:00")
    _ledger.append(bg_paths.ledger, bg_paths.key_file, entry)
    loaded = _ledger.load(bg_paths.ledger, bg_paths.key_file).entries[0]
    assert loaded.created_at == "2026-10-01T00:00"
    assert loaded.payload()["device"] == entry.device


def test_unverified_rows_are_kept_but_ignored(bg_paths: Paths) -> None:
    forged = {"entry_id": "forged", "kind": CREDIT, "hmac": "00"}
    _write_rows(bg_paths.ledger, [forged, "not a row"])
    entry = Entry(entry_id="real", kind=REJECT, day="2026-10-03")
    assert _ledger.append(bg_paths.ledger, bg_paths.key_file, entry)
    raw = json.loads(bg_paths.ledger.read_text(encoding="utf-8"))["entries"]
    assert raw[0] == forged
    assert raw[1] == "not a row"
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert [e.entry_id for e in ledger.entries] == ["real"]


def test_append_duplicate_of_unverified_row(bg_paths: Paths) -> None:
    _write_rows(bg_paths.ledger, [{"entry_id": "dup", "hmac": "bad"}])
    entry = Entry(entry_id="dup", kind=CREDIT, day="d")
    assert not _ledger.append(bg_paths.ledger, bg_paths.key_file, entry)


def test_append_refuses_without_key(bg_paths: Paths, tmp_path: Path) -> None:
    entry = Entry(entry_id="x", kind=CREDIT, day="d")
    with pytest.raises(OSError, match="unreadable"):
        _ledger.append(bg_paths.ledger, tmp_path / "nokey", entry)
    assert not bg_paths.ledger.exists()


def _base_row() -> dict[str, object]:
    return {
        "entry_id": "r",
        "kind": CREDIT,
        "day": "2026-10-01",
        "created_at": "2026-10-01T10:00:00+00:00",
        "amount": 3,
        "device": "pc",
        "detail": {"page": 7},
    }


@pytest.mark.parametrize(
    ("change", "valid"),
    [
        ({}, True),
        ({"detail": None}, True),
        ({"amount": "many"}, False),
        ({"detail": 5}, False),
        ({"device": None}, True),
    ],
)
def test_parse_signed_rows(
    bg_paths: Paths, change: dict[str, object], valid: bool
) -> None:
    row = {**_base_row(), **change}
    _write_rows(bg_paths.ledger, [_signed(row, bg_paths.key_file)])
    ledger = _ledger.load(bg_paths.ledger, bg_paths.key_file)
    assert len(ledger.entries) == int(valid)


def test_parse_signed_row_missing_field(bg_paths: Paths) -> None:
    row = _base_row()
    del row["day"]
    _write_rows(bg_paths.ledger, [_signed(row, bg_paths.key_file)])
    assert _ledger.load(bg_paths.ledger, bg_paths.key_file).entries == []


def test_parse_detail_values_stringified(bg_paths: Paths) -> None:
    _write_rows(bg_paths.ledger, [_signed(_base_row(), bg_paths.key_file)])
    entry = _ledger.load(bg_paths.ledger, bg_paths.key_file).entries[0]
    assert entry.detail == {"page": "7"}
    assert Ledger([entry]).has("r")
