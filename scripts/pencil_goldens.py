# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
# pylint: disable=too-many-locals  # offline numeric dev tool
"""Write the golden fixture the app's Dart port of the pencil reader must match.

``app/lib/src/pencil_*.dart`` ports ``book_guard/_pencil_*.py`` line for line.
This cuts margin crops out of the real labelled photos
(``~/data/book-guard_binaries/page_truth``), runs the Python finder on them,
and writes the pixels plus the answers, so a Dart test can demand identical
ones. It also stores the glyph masks the finder cut out, the 28x28 pictures
:func:`~book_guard._pencil_norm.normalise` made of them and the network's
probabilities for those, which pins the pieces separately.

    python3 -m scripts.pencil_goldens [OUT]      # from the repo root

Reading a photo is slow (Tesseract), so give a case name to refresh just that
one: ``python3 -m scripts.pencil_goldens --only pencil_1``. Run it as a module
so the tree's own ``book_guard`` is imported. The writer refuses a case whose
answer is not the one the photo truly shows.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import sys
from typing import Any
import zlib

import numpy as np

from book_guard._ocr import scan
from book_guard._pencil import column_body
from book_guard._pencil_blob import blobs, merge_glyphs
from book_guard._pencil_find import (
    FRACS,
    INK_STEP,
    find_number,
    glyph_mask,
    lone_patches,
    paper_map,
    shrink,
)
from book_guard._pencil_net import WEIGHTS, load
from book_guard._pencil_norm import normalise

_TRUTH = Path.home() / "data/book-guard_binaries/page_truth"
_OUT = Path(__file__).resolve().parent.parent / "app/test/fixtures/pencil_goldens.json"
_UNIT = 16
# name -> (photo, which margin, the number the photo truly shows or None)
_CASES = {
    "pencil_612": ("p612_stop_pencil.jpg", "below", 612),
    "pencil_1": ("p1_start_pencil.jpg", "above", 1),
    "pencil_29": ("p29_stop_pencil.jpg", "above", 29),
    "print_9_ornaments": ("p9_start_ornaments_a.jpg", "below", None),
    "print_502": ("p502_start_switched.jpg", "below", None),
}


def _scanned(photo: str) -> tuple[np.ndarray, tuple[int, int, int, int], float]:
    """The upright gray page, its text box and line height.

    Tesseract is slow: ``PENCIL_SCAN_CACHE=DIR`` keeps each photo's result.
    """
    cache = os.environ.get("PENCIL_SCAN_CACHE")
    path = Path(cache) / f"{photo}.npz" if cache else None
    if path is not None and path.exists():
        data = np.load(path)
        left, top, right, bottom = (int(v) for v in data["body"])
        return data["gray"], (left, top, right, bottom), float(data["line"])
    page = scan(_TRUTH / photo)
    if page is None:
        raise SystemExit(f"cannot read {photo}")
    body, line = column_body(page)
    gray = np.asarray(page.image.convert("L"))
    if path is not None:
        np.savez(path, gray=gray, body=np.array(body), line=line)
    return gray, body, line


def _canvas(name: str) -> dict[str, Any]:
    photo, margin, _ = _CASES[name]
    gray, body, line = _scanned(photo)
    factor = max(1, int(line // _UNIT))
    unit = line / factor
    small = shrink(gray, factor)
    left, top, right, bottom = (v // factor for v in body)
    near = round(5 * unit)
    c0 = max(0, left - 40) if margin == "below" else 0
    c1 = min(small.shape[1], left + 190)
    if margin == "below":
        rows = (max(0, bottom - near), small.shape[0])
        inner = (left - c0, 0, min(right, c1) - c0, bottom - rows[0])
    else:
        rows = (0, top + near)
        inner = (left - c0, top, min(right, c1) - c0, top + near)
    crop = small[rows[0] : rows[1], c0:c1].astype(np.uint8)
    return {
        "name": name,
        "width": int(crop.shape[1]),
        "height": int(crop.shape[0]),
        "body": list(inner),
        "line": unit,
        "gray": base64.b64encode(zlib.compress(crop.tobytes(), 9)).decode(),
    }


def gray_of(case: dict[str, Any]) -> np.ndarray:
    """The case's pixels."""
    raw = zlib.decompress(base64.b64decode(str(case["gray"])))
    return np.frombuffer(raw, np.uint8).reshape(int(case["height"]), int(case["width"]))


def _answer(case: dict[str, Any]) -> int | None:
    left, top, right, bottom = (int(v) for v in case["body"])
    body = (left, top, right, bottom)
    return find_number(load(), gray_of(case), body, float(case["line"]))


def _masks(case: dict[str, Any]) -> list[dict[str, Any]]:
    """The glyph masks the finder cuts from the case, and what the net makes."""
    gray, unit = gray_of(case), float(case["line"])
    left, top, right, bottom = (int(v) for v in case["body"])
    diff = paper_map(shrink(gray, 1).astype(np.int64), round(2.0 * unit)) - gray
    pad = round(unit)
    found = []
    for rows in ((0, top), (bottom, gray.shape[0])):
        if rows[1] - rows[0] < unit:
            continue
        region = (rows[0], rows[1], max(0, left - pad), min(gray.shape[1], right + pad))
        for _, strokes in lone_patches(
            blobs(diff > INK_STEP, region, unit, 0.35), unit
        ):
            found += [glyph_mask(diff, g) for g in merge_glyphs(strokes)]
    net = load()
    out = []
    for mask in found:
        out.append(
            {
                "mask": ["".join("1" if v else "0" for v in row) for row in mask],
                "picture": [
                    round(float(v), 6) for v in normalise(mask, 0.14).reshape(-1)
                ],
                "probs": [
                    [round(float(v), 9) for v in net.probabilities(normalise(mask, f))]
                    for f in FRACS
                ],
            }
        )
    return out


def build(only: str | None, previous: dict[str, Any]) -> dict[str, Any]:
    """The fixture; with ``only``, just that case is read again."""
    old = {c["name"]: c for c in previous.get("cases", [])}
    cases = []
    for name, (_, _, truth) in _CASES.items():
        if only not in (None, name):
            if name in old:
                cases.append(old[name])
            continue
        case = _canvas(name)
        case["expected"] = _answer(case)
        if case["expected"] != truth:
            msg = f"{name}: the finder says {case['expected']}, the photo shows {truth}"
            raise SystemExit(msg)
        case["masks"] = _masks(case)
        cases.append(case)
    # A pencil-free copy of the 612 margin: the same paper, no number.
    source = [c for c in cases if c["name"] == "pencil_612"]
    if not source:
        return {
            "weights_sha256": hashlib.sha256(WEIGHTS.read_bytes()).hexdigest(),
            "cases": cases,
        }
    blank = dict(source[0])
    gray = gray_of(blank).copy()
    below = int(blank["body"][3]) + 4
    gray[below:, :] = int(np.median(gray[below : below + 12, :]))
    blank |= {
        "name": "blank_margin",
        "gray": base64.b64encode(zlib.compress(gray.tobytes(), 9)).decode(),
    }
    blank["expected"], blank["masks"] = _answer(blank), []
    if blank["expected"] is not None:
        raise SystemExit("blank_margin is not blank")
    cases.append(blank)
    return {
        "weights_sha256": hashlib.sha256(WEIGHTS.read_bytes()).hexdigest(),
        "cases": cases,
    }


def main() -> int:
    """Write the fixture."""
    args = sys.argv[1:]
    only = args[args.index("--only") + 1] if "--only" in args else None
    positional = [
        a
        for i, a in enumerate(args)
        if a != "--only" and (i == 0 or args[i - 1] != "--only")
    ]
    out = Path(positional[0]) if positional else _OUT
    previous = json.loads(out.read_text(encoding="utf-8")) if out.exists() else {}
    out.write_text(
        json.dumps(build(only, previous), separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    sys.stdout.write(f"{out} {out.stat().st_size} bytes\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
