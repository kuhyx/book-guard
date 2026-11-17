# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The pre-commit gate itself: hooks that must fit the 2 GiB capped.sh scope."""

from __future__ import annotations

from pathlib import Path
import re

_CONFIG = Path(__file__).resolve().parents[2] / ".pre-commit-config.yaml"


def _entry(hook_id: str) -> str:
    text = _CONFIG.read_text(encoding="utf-8")
    match = re.search(
        rf"- id: {re.escape(hook_id)}\n(?:\s+(?!- id:).*\n)*?\s+entry: (.*)\n", text
    )
    assert match is not None, f"no entry for hook {hook_id}"
    return match.group(1)


def test_app_tests_run_one_isolate_at_a_time() -> None:
    """``flutter test -j 2`` peaks at ~1.7 GiB anon: OOM-killed in the 2 GiB scope.

    Measured 2026-11-17 (scope memory.stat anon): -j 2 1680 MiB, -j 1 1073 MiB.
    The checks run of pre-commit --all-files was killed (exit -15) in it.
    """
    assert re.search(r"flutter test -j 1(\s|')", _entry("app-test"))
