# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""deploy.sh builds the phone APK in phone_deploy stages, never one gradle run.

A one-shot `phone_deploy.sh --release` is a single `flutter build apk`
(57-64 s), which held a build slot past the 60 s cap (perf.heavybuild).
"""

from __future__ import annotations

from pathlib import Path
import re

SCRIPT: Path = Path(__file__).resolve().parents[2] / "scripts" / "deploy.sh"

_STAGES = (
    "--stage prep",
    "kernel",
    "aot",
    "dart",
    "kotlin",
    "assemble",
    "--stage install",
)


def _code_lines() -> list[str]:
    return [
        line
        for line in SCRIPT.read_text().splitlines()
        if not line.lstrip().startswith("#")
    ]


def test_every_phone_deploy_call_is_staged() -> None:
    calls = [line for line in _code_lines() if '"${PHONE_DEPLOY}"' in line]
    assert calls, "deploy.sh no longer calls phone_deploy.sh"
    for line in calls:
        assert "--stage" in line, f"one-shot phone_deploy build: {line!r}"


def test_all_build_stages_run_in_order() -> None:
    code = "\n".join(_code_lines())
    start = code.find("phone_build_and_install() {")
    assert start != -1, "phone_build_and_install() missing"
    body = code[start : code.find("\n}", start)]
    positions = [body.find(stage) for stage in _STAGES]
    assert all(pos != -1 for pos in positions), dict(
        zip(_STAGES, positions, strict=True)
    )
    assert positions == sorted(positions), dict(zip(_STAGES, positions, strict=True))


def test_heavy_stages_run_capped() -> None:
    code = "\n".join(_code_lines())
    assert re.search(r"CAP_MEM=4G\s+\"\$\{CAPPED\}\"", code), (
        "the dart/kotlin/assemble stages must run under capped.sh at 4G"
    )
