# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""book-guard's own exception types."""

from __future__ import annotations


class CorruptFileError(ValueError):
    """A state file exists but is not what it should be.

    Never treated as empty: an unreadable ledger read as "no entries" would
    erase every credit. A ``ValueError`` so existing handlers still catch it.
    """
