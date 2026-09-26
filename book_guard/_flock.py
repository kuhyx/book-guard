# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""One writer at a time across every book-guard process.

The path unit, the fallback timer and the lock window's poll can all run a
pass at once, and each pass is read-modify-write on the photo cache and the
ledger -- plus a paid vision call per photo. An exclusive ``flock`` on one
file in the data dir serialises whole passes; the kernel drops it if the
holder dies, so it can never go stale.
"""

from __future__ import annotations

from contextlib import contextmanager
import fcntl
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterator

    from book_guard._paths import Paths


@contextmanager
def exclusive(paths: Paths) -> Iterator[None]:
    """Hold the book-guard write lock for the duration of the block."""
    paths.data_dir.mkdir(parents=True, exist_ok=True)
    with (paths.data_dir / "write.lock").open("w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)
