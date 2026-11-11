# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The small digit network that reads a pencilled page number. No LLM.

A plain MLP (784 -> hidden... -> 10, ReLU) trained on MNIST plus synthetic
European ones and sevens, by ``scripts/train_pencil.py``. Its one weights file,
``app/assets/pencil_digits.bin``, is read by this module on the PC and by
``app/lib/src/pencil_net.dart`` on the phone; the forward pass is float64 on
both sides and ``app/test/fixtures/pencil_goldens.json`` keeps them equal.

File layout, little-endian: ``b"PNCL"``, u32 layer count ``n``, ``n + 1`` u32
sizes (784 first, 10 last), then per layer the ``out x in`` weights row by row
and the ``out`` biases, all float32.
"""

from __future__ import annotations

from dataclasses import dataclass
from itertools import pairwise
from pathlib import Path
import struct
from typing import TYPE_CHECKING, Final

import numpy as np

if TYPE_CHECKING:
    from numpy.typing import NDArray

WEIGHTS: Final = Path(__file__).resolve().parent.parent / "app/assets/pencil_digits.bin"
_MAGIC: Final = b"PNCL"
_WORD: Final = 4


@dataclass(frozen=True)
class Net:
    """Layers of ``(weights, biases)``."""

    layers: tuple[tuple[NDArray[np.float64], NDArray[np.float64]], ...]

    def probabilities(self, picture: NDArray[np.float64]) -> NDArray[np.float64]:
        """Softmax over the ten digits for one 28x28 picture."""
        x = picture.reshape(-1)
        for index, (weights, biases) in enumerate(self.layers):
            x = weights @ x + biases
            if index < len(self.layers) - 1:
                x = np.maximum(x, 0.0)
        x = np.exp(x - x.max())
        return x / x.sum()


def parse(data: bytes) -> Net:
    """The network in ``data`` (the weights file's bytes)."""
    if data[:_WORD] != _MAGIC:
        msg = "not a pencil-digit weights file"
        raise ValueError(msg)
    (count,) = struct.unpack_from("<I", data, _WORD)
    sizes = struct.unpack_from(f"<{count + 1}I", data, 2 * _WORD)
    offset = (3 + count) * _WORD
    layers = []
    for fan_in, fan_out in pairwise(sizes):
        cells = fan_out * fan_in + fan_out
        flat = np.frombuffer(data, dtype="<f4", count=cells, offset=offset)
        offset += cells * _WORD
        flat = flat.astype(np.float64)
        layers.append(
            (flat[: fan_out * fan_in].reshape(fan_out, fan_in), flat[-fan_out:])
        )
    return Net(tuple(layers))


def dump(net: Net) -> bytes:
    """The weights file's bytes for ``net`` (what ``parse`` reads)."""
    sizes = [net.layers[0][0].shape[1], *(w.shape[0] for w, _ in net.layers)]
    head = _MAGIC + struct.pack(f"<{len(sizes) + 1}I", len(net.layers), *sizes)
    body = b"".join(
        w.astype("<f4").tobytes() + b.astype("<f4").tobytes() for w, b in net.layers
    )
    return head + body


def load() -> Net:
    """The shipped network."""
    return parse(WEIGHTS.read_bytes())
