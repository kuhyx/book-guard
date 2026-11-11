#!/usr/bin/env python3
# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
# pylint: disable=too-many-locals,no-member,line-too-long,wrong-import-position,unnecessary-comprehension  # offline numeric dev tool
"""Train the pencil-digit network in resumable chunks (each call < 60 s).

Usage (repo root, numpy only, no torch):

    PYTHONPATH=. python3 -m scripts.train_pencil [--dir DIR] [--epochs N]
                                                [--budget SECONDS] [--export]

One call trains until ``--budget`` seconds (default 40) have passed or the
planned ``--epochs`` (default 40) are done, saving a checkpoint after every
epoch; run it again to continue. ``--export`` writes
``app/assets/pencil_digits.bin`` from the checkpoint and prints the MNIST
test accuracy. Data and checkpoint live in ``DIR`` (default
``~/data/book-guard_binaries/pencil_train``), never in the repo.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import time
from typing import Any

# Before numpy loads: a capped cgroup plus many BLAS threads ran 70x slower.
os.environ.setdefault("OPENBLAS_NUM_THREADS", "2")
os.environ.setdefault("OMP_NUM_THREADS", "2")

import numpy as np

from book_guard._pencil_net import WEIGHTS, Net, dump
from scripts.pencil_data import drawn, mnist

_SIZES = (784, 128, 64, 11)  # ten digits + 10 = "not a digit"
_BATCH = 256
_DEFAULT_DIR = Path.home() / "data/book-guard_binaries/pencil_train"


def _warp(batch: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """Random rotation, slant, scale, shift (bilinear) of 28x28 pictures."""
    count = len(batch)
    angle = np.clip(rng.normal(0, 0.14, count), -0.32, 0.32)
    shear = rng.uniform(-0.3, 0.3, count)
    sx, sy = rng.uniform(0.8, 1.15, count), rng.uniform(0.85, 1.15, count)
    ys, xs = np.mgrid[0:28, 0:28].astype(np.float32) - 13.5
    cos, sin = np.cos(angle), np.sin(angle)
    # source = M @ (x, y) + t, M = rotation * shear * scale
    a = (cos + shear * sin) / sx
    b = (-sin + shear * cos) / sx
    c = sin / sy
    d = cos / sy
    src_x = (
        a[:, None, None] * xs
        + b[:, None, None] * ys
        + 13.5
        + rng.uniform(-1.5, 1.5, (count, 1, 1))
    )
    src_y = (
        c[:, None, None] * xs
        + d[:, None, None] * ys
        + 13.5
        + rng.uniform(-1.5, 1.5, (count, 1, 1))
    )
    x0, y0 = np.floor(src_x).astype(int), np.floor(src_y).astype(int)
    fx, fy = src_x - x0, src_y - y0
    out = np.zeros_like(batch)
    index = np.arange(count)[:, None, None]
    for dy, wy in ((0, 1 - fy), (1, fy)):
        for dx, wx in ((0, 1 - fx), (1, fx)):
            yy, xx = y0 + dy, x0 + dx
            ok = (yy >= 0) & (yy < 28) & (xx >= 0) & (xx < 28)
            out += (
                np.where(ok, batch[index, np.clip(yy, 0, 27), np.clip(xx, 0, 27)], 0)
                * wy
                * wx
            )
    return out


def _morph(batch: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """Some pictures thinner, some thicker, some fainter, plus a little noise."""
    pad = np.pad(batch, ((0, 0), (1, 1), (1, 1)))
    stack = np.stack(
        [pad[:, i : i + 28, j : j + 28] for i in range(3) for j in range(3)]
    )
    kind = rng.random(len(batch))[:, None, None]
    out = np.where(kind < 0.25, stack.min(0), np.where(kind < 0.5, stack.max(0), batch))
    out = out * rng.uniform(0.6, 1.0, (len(batch), 1, 1)) + rng.normal(
        0, 0.03, out.shape
    )
    return np.clip(out, 0, 1).astype(np.float32)


def _recentre_batch(batch: np.ndarray) -> np.ndarray:
    """:func:`book_guard._pencil_norm.recentre` for a whole batch at once."""
    mass = batch.sum((1, 2))
    ys, xs = np.mgrid[0:28, 0:28]
    safe = np.where(mass > 0, mass, 1.0)
    shift_y = np.floor(13.5 - (batch * ys).sum((1, 2)) / safe + 0.5).astype(int)
    shift_x = np.floor(13.5 - (batch * xs).sum((1, 2)) / safe + 0.5).astype(int)
    src_y = ys[None] - shift_y[:, None, None]
    src_x = xs[None] - shift_x[:, None, None]
    ok = (src_y >= 0) & (src_y < 28) & (src_x >= 0) & (src_x < 28)
    index = np.arange(len(batch))[:, None, None]
    return np.where(ok, batch[index, np.clip(src_y, 0, 27), np.clip(src_x, 0, 27)], 0)


def _augment(batch: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    return _recentre_batch(_morph(_warp(batch, rng), rng).astype(np.float64)).astype(
        np.float32
    )


def _init(rng: np.random.Generator) -> dict[str, np.ndarray]:
    state: dict[str, np.ndarray] = {"epoch": np.array(0)}
    for i, (fan_in, fan_out) in enumerate(zip(_SIZES, _SIZES[1:], strict=False)):
        state[f"w{i}"] = (rng.normal(0, np.sqrt(2 / fan_in), (fan_out, fan_in))).astype(
            np.float32
        )
        state[f"b{i}"] = np.zeros(fan_out, dtype=np.float32)
    for key in [k for k in state if k[0] in "wb"]:
        state[f"m_{key}"] = np.zeros_like(state[key])
        state[f"v_{key}"] = np.zeros_like(state[key])
    state["step"] = np.array(0)
    return state


def _forward(state: dict[str, np.ndarray], x: np.ndarray) -> list[np.ndarray]:
    acts = [x]
    for i in range(len(_SIZES) - 1):
        z = acts[-1] @ state[f"w{i}"].T + state[f"b{i}"]
        acts.append(np.maximum(z, 0) if i < len(_SIZES) - 2 else z)
    return acts


def _step(
    state: dict[str, np.ndarray], x: np.ndarray, y: np.ndarray, rate: float
) -> None:
    acts = _forward(state, x)
    logits = acts[-1] - acts[-1].max(1, keepdims=True)
    prob = np.exp(logits)
    prob /= prob.sum(1, keepdims=True)
    target = np.full_like(
        prob, 0.05 / (_SIZES[-1] - 1)
    )  # label smoothing keeps the confidence honest
    target[np.arange(len(y)), y] = 0.95
    grad = (prob - target) / len(y)
    state["step"] = state["step"] + 1
    t = int(state["step"])
    for i in reversed(range(len(_SIZES) - 1)):
        gw, gb = grad.T @ acts[i], grad.sum(0)
        if i:
            grad = (grad @ state[f"w{i}"]) * (acts[i] > 0)
        for name, g in ((f"w{i}", gw), (f"b{i}", gb)):
            m, v = state[f"m_{name}"], state[f"v_{name}"]
            m *= 0.9
            m += 0.1 * g
            v *= 0.999
            v += 0.001 * g * g
            state[name] -= (
                rate * (m / (1 - 0.9**t)) / (np.sqrt(v / (1 - 0.999**t)) + 1e-8)
            )


def _accuracy(state: dict[str, np.ndarray], x: np.ndarray, y: np.ndarray) -> float:
    return float((_forward(state, x.reshape(len(x), -1))[-1].argmax(1) == y).mean())


def _net(state: dict[str, np.ndarray]) -> Net:
    return Net(
        tuple(
            (state[f"w{i}"].astype(np.float64), state[f"b{i}"].astype(np.float64))
            for i in range(len(_SIZES) - 1)
        )
    )


def main() -> int:
    """Train one chunk, or export."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", type=Path, default=_DEFAULT_DIR)
    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--budget", type=float, default=40.0)
    parser.add_argument("--export", action="store_true")
    args = parser.parse_args()
    started = time.monotonic()
    checkpoint = args.dir / "checkpoint.npz"
    state = _init(np.random.default_rng(1))
    if checkpoint.exists():
        state = {k: v for k, v in np.load(checkpoint).items()}
    train_x, train_y, test_x, test_y = mnist(args.dir)
    if args.export:
        WEIGHTS.parent.mkdir(parents=True, exist_ok=True)
        WEIGHTS.write_bytes(dump(_net(state)))
        sys.stdout.write(
            f"epoch {int(state['epoch'])} test {_accuracy(state, test_x, test_y):.4f} -> {WEIGHTS}\n"
        )
        return 0
    extra_x, extra_y = drawn(4000, 7)
    all_x, all_y = (
        np.concatenate([train_x, extra_x]),
        np.concatenate([train_y, extra_y]),
    )
    while (
        int(state["epoch"]) < args.epochs and time.monotonic() - started < args.budget
    ):
        epoch = int(state["epoch"])
        rng = np.random.default_rng(100 + epoch)
        rate = 2e-3 * (0.5 * (1 + np.cos(np.pi * epoch / args.epochs))) + 5e-5
        order = rng.permutation(len(all_x))
        for start in range(0, len(order), _BATCH):
            idx = order[start : start + _BATCH]
            _step(
                state, _augment(all_x[idx], rng).reshape(len(idx), -1), all_y[idx], rate
            )
        state["epoch"] = np.array(epoch + 1)
        arrays: dict[str, Any] = dict(state)
        np.savez(checkpoint, **arrays)
        sys.stdout.write(
            f"epoch {epoch + 1} test {_accuracy(state, test_x, test_y):.4f} {time.monotonic() - started:.0f}s\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
