# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""_pencil_net: the weights file and the MLP forward pass."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pytest

from book_guard import _pencil_net as net

FIXTURE = Path(__file__).parents[2] / "app/test/fixtures/pencil_goldens.json"


def _tiny() -> net.Net:
    first = np.zeros((3, 784))
    first[0, 0], first[1, 1] = 1.0, 1.0
    second = np.array([[1.0, 0.0, 0.0], [0.0, 2.0, 0.0]])
    return net.Net(
        ((first, np.array([0.0, 0.0, -1.0])), (second, np.array([0.5, 0.0])))
    )


def test_dump_then_parse_is_the_same_network() -> None:
    tiny = _tiny()
    again = net.parse(net.dump(tiny))
    picture = np.zeros((28, 28))
    picture[0, 0] = 2.0
    assert [w.shape for w, _ in again.layers] == [(3, 784), (2, 3)]
    assert np.allclose(again.probabilities(picture), tiny.probabilities(picture))


def test_probabilities_are_a_softmax_with_relu_between_layers() -> None:
    picture = np.zeros((28, 28))
    picture[0, 0] = 2.0  # hidden: [2, 0, relu(-1)=0]; logits: [2.5, 0]
    probs = _tiny().probabilities(picture)
    assert probs.sum() == pytest.approx(1.0)
    assert probs[0] == pytest.approx(1 / (1 + np.exp(-2.5)))


def test_a_file_that_is_not_weights_is_refused() -> None:
    with pytest.raises(ValueError, match="not a pencil-digit weights file"):
        net.parse(b"nope" + bytes(40))


def test_the_shipped_weights_are_the_ones_the_dart_fixture_was_made_with() -> None:
    shipped = hashlib.sha256(net.WEIGHTS.read_bytes()).hexdigest()
    pinned = json.loads(FIXTURE.read_text(encoding="utf-8"))["weights_sha256"]
    assert shipped == pinned, "retrain, then python3 -m scripts.pencil_goldens"
    loaded = net.load()
    assert loaded.layers[0][0].shape[1] == 784
    assert loaded.layers[-1][0].shape[0] == 11
