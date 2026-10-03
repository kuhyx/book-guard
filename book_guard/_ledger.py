# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The signed, append-only ledger -- the only state that carries value.

Same row shape as leetcode-guard's ledger (``entry_id``, ``kind``, ``day``,
``created_at``, ``amount``, ``device``, ``detail``, ``hmac``) and the same key,
so screen-locker and steam-backlog-enforcer verify a reading credit with the
exact ``gatelock.log_integrity.verify_entry_hmac(row)`` call they already use
for a LeetCode one.

Kinds:

* ``book`` -- a registered book (``isbn``, ``title``, ``author``, ``pages``).
  The newest one is the book being read.
* ``credit`` -- a session that passed the quiz. ``amount`` is its page count;
  ``detail.ended_at`` (unix seconds) is when the reading happened, which is
  the day the bonus belongs to, not the day the quiz was taken.
* ``reject`` -- a session that failed the quiz. Worth nothing, and final.
* ``escape`` -- a day whose lock was forgiven. Worth nothing either.

Tamper-evident, not tamper-proof: the key is world-readable, exactly as for
the sibling lockers.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
import json
import logging
import socket
from typing import TYPE_CHECKING, Final

from gatelock.log_integrity import compute_entry_hmac, verify_entry_hmac

from book_guard._atomic_json import write_json
from book_guard._errors import CorruptFileError

if TYPE_CHECKING:
    from pathlib import Path

_logger: Final = logging.getLogger(__name__)

BOOK: Final = "book"
CREDIT: Final = "credit"
REJECT: Final = "reject"
ESCAPE: Final = "escape"

_DEVICE: Final = socket.gethostname()


@dataclass(frozen=True)
class Entry:
    """One ledger row. ``detail`` values are strings, as in leetcode-guard."""

    entry_id: str
    kind: str
    day: str
    amount: int = 0
    detail: dict[str, str] = field(default_factory=dict)
    created_at: str = ""
    device: str = _DEVICE

    def payload(self) -> dict[str, object]:
        """The signed portion of the row."""
        return {
            "entry_id": self.entry_id,
            "kind": self.kind,
            "day": self.day,
            "created_at": self.created_at,
            "amount": self.amount,
            "device": self.device,
            "detail": dict(self.detail),
        }


@dataclass
class Ledger:
    """The verified entries, in file order."""

    entries: list[Entry] = field(default_factory=list)

    def has(self, entry_id: str) -> bool:
        """Whether an entry with this id is already recorded."""
        return any(e.entry_id == entry_id for e in self.entries)

    def of_kind(self, kind: str) -> list[Entry]:
        """Every verified entry of one kind, oldest first."""
        return [e for e in self.entries if e.kind == kind]

    def verdicts(self) -> dict[str, list[Entry]]:
        """Credit/reject rows by session id, oldest first.

        A rewritten summary's row is ``<session>#2``, so it groups with the
        first verdict instead of colliding with it (``append`` keeps ids unique).
        """
        found: dict[str, list[Entry]] = {}
        for entry in self.entries:
            if entry.kind in {CREDIT, REJECT}:
                found.setdefault(entry.entry_id.split("#")[0], []).append(entry)
        return found


def key_usable(key_file: Path) -> bool:
    """Whether signing is possible at all -- the gate refuses to run without."""
    return compute_entry_hmac({"probe": "1"}, key_file=key_file) is not None


def _parse(row: object, key_file: Path) -> Entry | None:
    """A stored row as an :class:`Entry`, or ``None`` if unusable or forged."""
    if not isinstance(row, dict) or not verify_entry_hmac(row, key_file=key_file):
        return None
    detail = row.get("detail")
    try:
        return Entry(
            entry_id=str(row["entry_id"]),
            kind=str(row["kind"]),
            day=str(row["day"]),
            amount=int(row["amount"]),
            detail={str(k): str(v) for k, v in dict(detail or {}).items()},
            created_at=str(row["created_at"]),
            device=str(row["device"]),
        )
    except KeyError, TypeError, ValueError:
        _logger.warning("ledger row %r is malformed; not counted", row.get("entry_id"))
        return None


def _raw_rows(path: Path) -> list[object]:
    """The file's entry array; a missing file is an empty ledger."""
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        _logger.warning("no ledger at %s yet; treating it as empty", path)
        return []
    rows = raw.get("entries") if isinstance(raw, dict) else None
    if not isinstance(rows, list):
        msg = f"{path} has no entries array"
        raise CorruptFileError(msg)
    return rows


def load(path: Path, key_file: Path) -> Ledger:
    """Read the ledger, keeping only rows whose signature verifies.

    Raises:
        ValueError: The file exists but is not a ledger. Never silently
            treated as empty -- that would erase every credit.
    """
    parsed = (_parse(row, key_file) for row in _raw_rows(path))
    return Ledger([e for e in parsed if e is not None])


def append(path: Path, key_file: Path, entry: Entry) -> bool:
    """Sign and append ``entry`` unless its id is already recorded.

    Unverified rows already in the file are preserved as they are: an entry
    the key cannot verify is evidence, not garbage.

    Returns:
        Whether anything was written.

    Raises:
        OSError: The key is unreadable or the write failed.
    """
    rows = _raw_rows(path)
    if any(isinstance(r, dict) and r.get("entry_id") == entry.entry_id for r in rows):
        return False
    stamped = Entry(
        entry_id=entry.entry_id,
        kind=entry.kind,
        day=entry.day,
        amount=entry.amount,
        detail=dict(entry.detail),
        created_at=entry.created_at or datetime.now(tz=UTC).isoformat(),
        device=entry.device,
    )
    payload = stamped.payload()
    signature = compute_entry_hmac(payload, key_file=key_file)
    if signature is None:
        msg = f"integrity key {key_file} is unreadable; refusing to write"
        raise OSError(msg)
    payload["hmac"] = signature
    rows.append(payload)
    write_json(path, {"version": 1, "entries": rows}, indent=1)
    return True
