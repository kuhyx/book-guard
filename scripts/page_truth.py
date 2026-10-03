#!/usr/bin/env python3
# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Gate: the local page reader against real, labelled page photos.

Runs :func:`book_guard._reader.read` on every row of
``~/data/book-guard_binaries/page_truth/manifest.json`` (photos live outside
the repo) and exits 1 on any mismatch. A row whose ``page`` is null must come
back with *no* page number -- "not found" is acceptable, a wrong number never
is. Re-run after touching ``_ocr.py``, ``_pagenum.py`` or ``_reader.py``.

Usage (from the repo root): python3 scripts/page_truth.py [TRUTH_DIR]
"""

from __future__ import annotations

import json
from pathlib import Path
import sys
import time

from book_guard._pagenum import Box, Context
from book_guard._reader import read

_DEFAULT_DIR = Path.home() / "data/book-guard_binaries/page_truth"


def _int_or_none(raw: object) -> int | None:
    return raw if isinstance(raw, int) else None


def _box(raw: object) -> Box | None:
    if not isinstance(raw, list):
        return None
    left, top, right, bottom = (int(v) for v in raw)
    return left, top, right, bottom


def _context(raw: object) -> Context:
    fields = raw if isinstance(raw, dict) else {}
    return Context(**{k: _int_or_none(v) for k, v in fields.items()})


def _row_ok(truth_dir: Path, row: dict[str, object]) -> bool:
    started = time.monotonic()
    box = _box(row.get("box"))
    reading = read(truth_dir / str(row["file"]), _context(row.get("context")), box)
    want_kind = row.get("kind")
    ok = reading.page_number == row["page"] and (
        want_kind is None or reading.kind == want_kind
    )
    mark = "ok  " if ok else "FAIL"
    took = time.monotonic() - started
    sys.stdout.write(
        f"{mark} {row['file']:<26} box={bool(box)!s:<5} want={row['page']!s:<5} "
        f"got={reading.page_number!s:<5} kind={reading.kind:<6} "
        f"turn={reading.rotation:<3} {took:4.1f}s {reading.reason}\n"
    )
    return ok


def main() -> int:
    """Run every labelled photo; 0 only if all match."""
    truth_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else _DEFAULT_DIR
    rows = json.loads((truth_dir / "manifest.json").read_text(encoding="utf-8"))
    failures = sum(not _row_ok(truth_dir, row) for row in rows)
    sys.stdout.write(f"{len(rows) - failures}/{len(rows)} match\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
