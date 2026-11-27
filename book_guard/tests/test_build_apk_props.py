# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Test that build_apk.sh uses shared gradle properties and no flutter build apk."""

from __future__ import annotations

from pathlib import Path
import re
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Callable
    import subprocess


SCRIPT: Path = Path(__file__).resolve().parents[2] / "scripts" / "build_apk.sh"


def _read_script() -> str:
    return SCRIPT.read_text()


def test_no_flutter_build_apk_outside_comments() -> None:
    content = _read_script()
    for i, line in enumerate(content.splitlines(), 1):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        if "flutter build apk" in line and "--config-only" not in line:
            pytest.fail(
                f"Line {i}: 'flutter build apk' found outside comment: {line!r}"
            )


def test_every_case_runs_flutter_config_before_gradlew() -> None:
    content = _read_script()
    for name in ("aot", "native", "apk", "aot-debug", "native-debug", "apk-debug"):
        match = re.search(
            rf"^    {name}\)(.*?)^ *;;$", content, re.MULTILINE | re.DOTALL
        )
        assert match, f"case branch '{name}' not found in {SCRIPT}"
        body = match.group(1)
        config_pos = body.find("flutter_config")
        gradlew_pos = body.find("gradlew")
        assert config_pos != -1, f"case '{name}' has no flutter_config call"
        assert gradlew_pos != -1, f"case '{name}' has no gradlew call"
        assert config_pos < gradlew_pos, (
            f"case '{name}' runs gradlew before flutter_config"
        )


def test_every_gradlew_call_uses_props_array() -> None:
    content = _read_script()
    for i, line in enumerate(content.splitlines(), 1):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        if "gradlew" in line and "${PROPS[@]}" not in line:
            pytest.fail(f"Line {i}: gradlew call without PROPS array: {line!r}")


def test_tree_shake_icons_in_props_function() -> None:
    content = _read_script()
    assert "-Ptree-shake-icons=" in content, (
        "gradle_props function missing -Ptree-shake-icons="
    )


def test_usage_exit_code(
    run_script: Callable[..., subprocess.CompletedProcess[str]],
) -> None:
    result = run_script(
        ["bash", str(SCRIPT)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 2, f"Expected exit 2, got {result.returncode}"
    assert "usage:" in result.stderr.lower(), (
        f"Usage line missing from stderr: {result.stderr!r}"
    )
