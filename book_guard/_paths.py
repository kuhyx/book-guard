# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Every on-disk location book-guard reads or writes.

Resolved through :func:`paths` at call time, never captured at import, so the
test suite's conftest can point the whole tree at a temp directory with one
patch. A module-level constant copied into another module is exactly how a
suite once wrote 27 fake entries into a live screen-locker log.
"""

from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
from typing import Final

_REAL_KEY: Final = Path("/etc/workout-locker/hmac.key")


@dataclass(frozen=True)
class Paths:
    """The locations of one book-guard installation.

    Attributes:
        data_dir: Private state (ledger, photo cache).
        reading_dir: The WebDAV-served folder the phone uploads into.
        key_file: The HMAC key shared with the sibling lockers.
    """

    data_dir: Path
    reading_dir: Path
    key_file: Path

    @property
    def ledger(self) -> Path:
        """The signed, append-only ledger other apps read for the bonus."""
        return self.data_dir / "ledger.json"

    @property
    def photos(self) -> Path:
        """What each uploaded photo was read as, keyed by content hash."""
        return self.data_dir / "photos.json"

    @property
    def inbox(self) -> Path:
        """Where the phone drops new photos (dufs-cloud upload)."""
        return self.reading_dir / "inbox"

    @property
    def processed(self) -> Path:
        """Where a photo moves once it has been read."""
        return self.reading_dir / "processed"

    @property
    def requests(self) -> Path:
        """Where the app drops request files."""
        return self.reading_dir / "requests"

    @property
    def responses(self) -> Path:
        """Where answers to request files go."""
        return self.reading_dir / "responses"

    @property
    def books(self) -> Path:
        """Where a book file (epub/pdf/...) is dropped to be attached."""
        return self.reading_dir / "books"

    @property
    def state_file(self) -> Path:
        """The app-readable snapshot (JSON twin of NEXT.txt)."""
        return self.reading_dir / "state.json"

    @property
    def next_file(self) -> Path:
        """The phone-readable "what to do next" note."""
        return self.reading_dir / "NEXT.txt"


def _default() -> Paths:
    # BOOK_GUARD_ROOT: a sandbox tree for demos and manual runs, so trying
    # the pipeline never touches the real ledger or the phone's inbox.
    root = os.environ.get("BOOK_GUARD_ROOT")
    if root:
        return Paths(
            data_dir=Path(root) / "data",
            reading_dir=Path(root) / "Reading",
            key_file=_REAL_KEY,
        )
    home = Path.home()
    return Paths(
        data_dir=home / ".local/share/book_guard",
        reading_dir=home / "data/cloud/Reading",
        key_file=_REAL_KEY,
    )


# A one-slot holder rather than a rebindable global: mutating a dict needs no
# ``global`` statement, and there is exactly one override at a time.
_override: dict[str, Paths] = {}


def paths() -> Paths:
    """The active locations: the real ones, or the test suite's override."""
    return _override.get("paths") or _default()


def set_override(value: Paths | None) -> None:
    """Point every path at ``value`` (tests), or back at the real tree."""
    _override.clear()
    if value is not None:
        _override["paths"] = value
