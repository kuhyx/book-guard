# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``--evening``: the orchestrator's exit code and the CLI flag."""

from __future__ import annotations

from types import SimpleNamespace
from typing import TYPE_CHECKING, Any

import pytest

from book_guard import _cli, _evening
from book_guard.tests._flow_helpers import LOCKED_DAY
from book_guard.tests._flow_helpers_lock import install_lock_fakes

if TYPE_CHECKING:
    from book_guard._paths import Paths


# the exit code the orchestrator names -----------------------------------------


def test_end_code_comes_from_the_orchestrator_when_it_exists() -> None:
    module = SimpleNamespace(EXIT_END_EVENING=42)
    assert _evening.end_code(lambda _name: module) == 42


def test_end_code_falls_back_to_10(caplog: pytest.LogCaptureFixture) -> None:
    def missing(_name: str) -> object:
        raise ImportError

    assert _evening.end_code(missing) == 10
    assert "evening_chain missing" in caplog.text
    assert _evening.end_code(lambda _name: object()) == 10


# the flag --------------------------------------------------------------------


def test_cli_flag_runs_the_evening_gate(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[dict[str, Any]] = []

    def fake(_paths: object, **kwargs: Any) -> int:
        calls.append(kwargs)
        return 10

    monkeypatch.setattr(_cli, "run_evening", fake)
    assert _cli.main(["lock", "--production", "--evening"]) == 10
    assert calls == [{"production": True, "today": None}]


def test_cli_without_the_flag_is_the_normal_gate(
    bg_paths: Paths, monkeypatch: pytest.MonkeyPatch
) -> None:
    install_lock_fakes(monkeypatch)
    monkeypatch.setattr(_cli, "run_evening", lambda *_a, **_k: pytest.fail("evening"))
    assert _cli.main(["lock", "--today", LOCKED_DAY.isoformat()]) == 0
