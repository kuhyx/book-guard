# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
# pylint: disable=too-many-locals,no-member,line-too-long  # offline numeric dev tool
"""Training pictures for the pencil-digit network: MNIST plus drawn 1s and 7s.

MNIST is mostly American handwriting; a pencilled page number is often a
European 1 (a long flag on the stem) that an MNIST-only network calls a 7.
So the drawn sets teach the difference: ones with a flag, a plain stem or a
foot, and sevens with a bar and a stem, with or without a cross-stroke.
Everything is 28x28 float32 in [0, 1], ink = 1.
"""

from __future__ import annotations

import gzip
from pathlib import Path
import urllib.request

import numpy as np
from numpy.typing import NDArray

from book_guard._pencil_norm import normalise

_BASE = "https://storage.googleapis.com/cvdf-datasets/mnist/"
_FILES = (
    "train-images-idx3-ubyte.gz",
    "train-labels-idx1-ubyte.gz",
    "t10k-images-idx3-ubyte.gz",
    "t10k-labels-idx1-ubyte.gz",
)
Pictures = NDArray[np.float32]


def _fetch(directory: Path, name: str) -> bytes:
    path = directory / name
    if not path.exists():
        directory.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(_BASE + name, timeout=30) as reply:
            path.write_bytes(reply.read())
    return gzip.decompress(path.read_bytes())


def mnist(
    directory: Path,
) -> tuple[Pictures, NDArray[np.int64], Pictures, NDArray[np.int64]]:
    """``(train images, train labels, test images, test labels)``."""
    raw = [_fetch(directory, name) for name in _FILES]
    images = [
        np.frombuffer(r, np.uint8, offset=16).reshape(-1, 28, 28) / np.float32(255)
        for r in (raw[0], raw[2])
    ]
    labels = [
        np.frombuffer(r, np.uint8, offset=8).astype(np.int64) for r in (raw[1], raw[3])
    ]
    return (
        images[0].astype(np.float32),
        labels[0],
        images[1].astype(np.float32),
        labels[1],
    )


def _stroke(points: list[tuple[float, float]], thick: float) -> NDArray[np.float32]:
    """A pen line through ``points`` (x, y) on a 28x28 field, ``thick`` px wide."""
    ys, xs = np.mgrid[0:28, 0:28].astype(np.float32)
    dist = np.full((28, 28), 99.0, dtype=np.float32)
    for (x0, y0), (x1, y1) in zip(points, points[1:], strict=False):
        dx, dy = x1 - x0, y1 - y0
        along = np.clip(
            ((xs - x0) * dx + (ys - y0) * dy) / (dx * dx + dy * dy + 1e-9), 0, 1
        )
        dist = np.minimum(
            dist, np.hypot(xs - (x0 + along * dx), ys - (y0 + along * dy))
        )
    return np.asarray(np.clip(thick / 2 + 0.5 - dist, 0, 1), dtype=np.float32)


def _one(rng: np.random.Generator) -> NDArray[np.float32]:
    cx, slant = rng.uniform(11, 17), rng.uniform(-3, 3)
    top, bottom = (
        (cx + slant / 2, rng.uniform(3, 6)),
        (cx - slant / 2, rng.uniform(22, 25)),
    )
    points = [top, bottom]
    pic = _stroke(points, rng.uniform(1.8, 3.2))
    if rng.random() < 0.65:  # the flag: a short stroke down and to the left
        flag = (top[0] - rng.uniform(3, 8), top[1] + rng.uniform(2.5, 8))
        pic = np.maximum(pic, _stroke([top, flag], rng.uniform(1.8, 3.0)))
    if rng.random() < 0.15:  # a foot
        half = rng.uniform(3, 6)
        pic = np.maximum(
            pic,
            _stroke(
                [(bottom[0] - half, bottom[1]), (bottom[0] + half, bottom[1])], 2.0
            ),
        )
    return pic


def _seven(rng: np.random.Generator) -> NDArray[np.float32]:
    left, right = rng.uniform(5, 10), rng.uniform(16, 22)
    y = rng.uniform(4, 7)
    foot = (right - rng.uniform(3, 9), rng.uniform(22, 25))
    pic = _stroke([(left, y), (right, y), foot], rng.uniform(1.8, 3.2))
    if rng.random() < 0.4:  # the European cross-stroke through the stem
        mid = y + (foot[1] - y) * rng.uniform(0.4, 0.6)
        reach = (right - foot[0]) * (mid - y) / (foot[1] - y)
        pic = np.maximum(
            pic, _stroke([(right - reach - 4, mid), (right - reach + 4, mid)], 2.0)
        )
    return pic


def drawn(count: int, seed: int) -> tuple[Pictures, NDArray[np.int64]]:
    """``count`` drawn ones and ``count`` drawn sevens, shuffled."""
    rng = np.random.default_rng(seed)
    images = np.stack(
        [_one(rng) for _ in range(count)] + [_seven(rng) for _ in range(count)]
    )
    labels = np.array([1] * count + [7] * count, dtype=np.int64)
    return images.astype(np.float32), labels


def _squiggle(rng: np.random.Generator) -> NDArray[np.float32]:
    """A scribble, an arc or a wave: what a swash or a smudge looks like."""
    kind = rng.integers(3)
    if kind == 0:
        points = [
            (rng.uniform(4, 24), rng.uniform(4, 24)) for _ in range(rng.integers(2, 6))
        ]
    elif kind == 1:
        centre, radius = rng.uniform(10, 18, 2), rng.uniform(5, 11)
        start, span = rng.uniform(0, 6.28), rng.uniform(1.5, 4.7)
        angles = start + np.linspace(0, span, 12)
        points = [
            (centre[0] + radius * np.cos(a), centre[1] + radius * np.sin(a))
            for a in angles
        ]
    else:
        amp, freq, tilt = (
            rng.uniform(2, 6),
            rng.uniform(0.3, 0.9),
            rng.uniform(-0.6, 0.6),
        )
        points = [
            (4 + t, 14 + amp * np.sin(freq * t) + tilt * t)
            for t in np.linspace(0, 20, 14)
        ]
    return _stroke(points, rng.uniform(1.8, 3.2))


def _fragment(image: Pictures, rng: np.random.Generator) -> NDArray[np.float32]:
    """A piece cut out of a digit: half a 6 is no digit."""
    mask = image > 0.5
    ys, xs = np.nonzero(mask)
    top, left = ys.min(), xs.min()
    height, width = ys.max() - top + 1, xs.max() - left + 1
    cut_y, cut_x = rng.uniform(0.35, 0.65) * height, rng.uniform(0.35, 0.65) * width
    row = (
        slice(int(top), int(top + cut_y))
        if rng.random() < 0.5
        else slice(int(top + cut_y), int(top + height))
    )
    col = (
        slice(int(left), int(left + cut_x))
        if rng.random() < 0.5
        else slice(int(left + cut_x), int(left + width))
    )
    keep = np.zeros_like(mask)
    if rng.random() < 0.5:
        keep[row] = mask[row]
    else:
        keep[:, col] = mask[:, col]
    return keep.astype(np.float32)


def rejects(
    source: Pictures, count: int, seed: int
) -> tuple[Pictures, NDArray[np.int64]]:
    """``count`` pictures of what is no digit (class 10), made like real glyphs.

    Each is cut tight, then squeezed by the same :func:`normalise` the finder
    uses, so the network sees what a stray patch becomes.
    """
    rng = np.random.default_rng(seed)
    made: list[NDArray[np.float64]] = []
    while len(made) < count:
        raw = (
            _squiggle(rng)
            if rng.random() < 0.55
            else _fragment(source[rng.integers(len(source))], rng)
        )
        ys, xs = np.nonzero(raw > 0.5)
        if len(ys) < 6:
            continue
        glyph = raw[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1] > 0.5
        made.append(normalise(glyph, rng.uniform(0.1, 0.2)))
    return np.stack(made).astype(np.float32), np.full(count, 10, dtype=np.int64)
