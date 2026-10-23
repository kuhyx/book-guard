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

from gatelock.morning_session import MORNING_SESSION_FILE
from gatelock.night_lockdown import NIGHT_LOCKDOWN_STAMP

from book_guard._share_paths import SharePaths

_REAL_KEY: Final = Path("/etc/workout-locker/hmac.key")


@dataclass(frozen=True)
class Paths(SharePaths):
    """The locations of one book-guard installation.

    Attributes:
        data_dir: Private state (ledger, photo cache).
        reading_dir: The WebDAV-served folder the phone uploads into.
        key_file: The HMAC key shared with the sibling lockers.
        morning_session: wake-alarm's signed morning (the 11:00 carrot).
        night_lockdown: night-lockdown's stamp; no re-arm after tonight's.
    """

    data_dir: Path
    reading_dir: Path
    key_file: Path
    morning_session: Path
    night_lockdown: Path

    @property
    def ledger(self) -> Path:
        """The signed, append-only ledger other apps read for the bonus."""
        return self.data_dir / "ledger.json"

    @property
    def photos(self) -> Path:
        """What each uploaded photo was read as, keyed by content hash."""
        return self.data_dir / "photos.json"

    @property
    def isbn_cache(self) -> Path:
        """What each ISBN lookup found, so a book is asked about rarely."""
        return self.data_dir / "isbn_cache.json"

    @property
    def lookup_sources(self) -> Path:
        """Per-source request times and rate-limit backoffs."""
        return self.data_dir / "lookup_sources.json"

    @property
    def google_key_file(self) -> Path:
        """Optional Google Books API key (one line); absent means anonymous."""
        return self.data_dir / "google_books_api_key"

    @property
    def claude_down(self) -> Path:
        """Present while Claude calls fail: when the outage began."""
        return self.data_dir / "claude_down.json"

    @property
    def session_times(self) -> Path:
        """Start/end times the reader narrowed, by session id."""
        return self.data_dir / "session_times.json"

    @property
    def index_job(self) -> Path:
        """Where the last dropped book file's indexing stands."""
        return self.data_dir / "index_job.json"

    @property
    def notes(self) -> Path:
        """The reader's notes per book, written from the app (never pruned)."""
        return self.data_dir / "notes.json"

    @property
    def summaries(self) -> Path:
        """Every summary in full, by verdict id (the ledger keeps 1000 chars)."""
        return self.data_dir / "summaries.json"

    @property
    def ebook_maps(self) -> Path:
        """Each book's page map (private: the app's copy is never read back)."""
        return self.data_dir / "ebook_maps"

    @property
    def ebook_sessions(self) -> Path:
        """Sessions read in the app, append-only (never pruned)."""
        return self.data_dir / "ebook_sessions.json"

    @property
    def reports(self) -> Path:
        """Filed bug reports: each photo and what was made of it."""
        return self.data_dir / "reports"


def _default() -> Paths:
    # BOOK_GUARD_ROOT: a sandbox tree for demos and manual runs, so trying
    # the pipeline never touches the real ledger or the phone's inbox.
    root = os.environ.get("BOOK_GUARD_ROOT")
    if root:
        return Paths(
            data_dir=Path(root) / "data",
            reading_dir=Path(root) / "Reading",
            key_file=_REAL_KEY,
            morning_session=Path(root) / "morning_session.json",
            night_lockdown=Path(root) / "locked_at_epoch",
        )
    home = Path.home()
    return Paths(
        data_dir=home / ".local/share/book_guard",
        reading_dir=home / "data/cloud/Reading",
        key_file=_REAL_KEY,
        morning_session=MORNING_SESSION_FILE,
        night_lockdown=NIGHT_LOCKDOWN_STAMP,
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
