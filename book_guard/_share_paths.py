# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The WebDAV share's layout (``Reading/``), as a base of :class:`Paths`.

Split from :mod:`book_guard._paths` so each class stays a readable size:
everything here is what the phone and the desktop app see -- the inbox,
the published views, requests and responses, logs -- while ``Paths``
keeps the private state under ``data_dir``.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pathlib import Path


class SharePaths:
    """Locations inside ``reading_dir``; :class:`Paths` supplies the field."""

    reading_dir: Path

    @property
    def error_log(self) -> Path:
        """Every failure, phone and PC, one JSON object per line."""
        return self.reading_dir / "logs" / "errors.jsonl"

    @property
    def uploaded_reports(self) -> Path:
        """Bug reports ("this should not have failed"), as uploaded."""
        return self.reading_dir / "logs" / "reports"

    @property
    def phone_logs(self) -> Path:
        """The phone's error entries, one file each, until merged."""
        return self.reading_dir / "logs" / "phone"

    @property
    def inbox(self) -> Path:
        """Where the phone drops new photos (dufs-cloud upload)."""
        return self.reading_dir / "inbox"

    @property
    def processed(self) -> Path:
        """Where a photo moves once it has been read."""
        return self.reading_dir / "processed"

    @property
    def thumbs(self) -> Path:
        """Small copies of the filed photos, for the app's gallery."""
        return self.reading_dir / "thumbs"

    @property
    def sessions(self) -> Path:
        """One detail file per session, for the app's history view."""
        return self.reading_dir / "sessions"

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
    def library_file(self) -> Path:
        """Every book with its sessions, full summaries and notes, for the app."""
        return self.reading_dir / "library.json"

    @property
    def next_file(self) -> Path:
        """The phone-readable "what to do next" note."""
        return self.reading_dir / "NEXT.txt"
