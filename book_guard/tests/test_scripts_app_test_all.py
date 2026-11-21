# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""scripts/app_test_all.sh: the whole app suite as slices, one flutter run each.

A single ``flutter test -j 1`` over every file held a build slot for 62 s
(2026-11-21). Each slice is its own ``flutter test`` process, so none holds
the slot for long; a ``K/N`` argument runs one slice, a call of its own.
"""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable
    import subprocess

    Run = Callable[..., subprocess.CompletedProcess[str]]

_REPO = Path(__file__).resolve().parents[2]
_SCRIPT = _REPO / "scripts" / "app_test_all.sh"
_MAX_FILES = 20
"""A slice took 31 s for 26 files beside an APK build: 20 keeps it near 25 s."""


def _runs(run_script: Run, tmp_path: Path, *args: str) -> list[list[str]]:
    """Run the script with a stub ``flutter``; the argv of each flutter run."""
    stub = tmp_path / "bin"
    stub.mkdir(parents=True)
    log = tmp_path / "flutter.log"
    # /usr/bin/fvm wins over flutter when present: stub both.
    for name, shift in (("flutter", ""), ("fvm", "shift\n")):
        tool = stub / name
        tool.write_text(f'#!/bin/bash\n{shift}echo "$*" >> "{log}"\n', encoding="utf-8")
        tool.chmod(0o755)
    done = run_script(
        ["bash", str(_SCRIPT), *args],
        env={"PATH": f"{stub}:/usr/bin:/bin", "HOME": str(tmp_path)},
        capture_output=True,
        text=True,
        check=False,
    )
    assert done.returncode == 0, done.stderr
    return [line.split() for line in log.read_text(encoding="utf-8").splitlines()]


def _all_tests() -> list[str]:
    test_dir = _REPO / "app" / "test"
    return sorted(
        p.relative_to(_REPO / "app").as_posix() for p in test_dir.rglob("*_test.dart")
    )


def test_the_whole_suite_runs_as_small_slices_each_file_once(
    run_script: Run, tmp_path: Path
) -> None:
    runs = _runs(run_script, tmp_path)
    assert len(runs) > 1
    files: list[str] = []
    for argv in runs:
        assert argv[:4] == ["test", "-j", "1", "--reporter=compact"]
        assert 0 < len(argv[4:]) <= _MAX_FILES
        files += argv[4:]
    assert sorted(files) == _all_tests()


def test_one_slice_runs_alone(run_script: Run, tmp_path: Path) -> None:
    whole = _runs(run_script, tmp_path / "a")
    assert _runs(run_script, tmp_path / "b", f"2/{len(whole)}") == [whole[1]]
