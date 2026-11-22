# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""scripts/app_test_changed.sh: the commit gate's app tests, at most 6 files.

A deps bump (app/pubspec.lock) ran the whole app suite inside one
``pre-commit run`` and held a build slot past 60 s (2026-11-22). The hook now
starts at most ``GATE_MAX`` test files, changed tests first; CI (app.yml)
runs the whole suite.
"""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable
    import subprocess

    Run = Callable[..., subprocess.CompletedProcess[str]]

_REPO = Path(__file__).resolve().parents[2]
_SCRIPT = _REPO / "scripts" / "app_test_changed.sh"
_GATE_MAX = 6
"""The rest of the gate takes ~45 s; 6 files at ~1.3 s each keeps it under 60 s."""
_HEAD = ["test", "-j", "1", "--reporter=compact"]


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
        cwd=_REPO,
        env={"PATH": f"{stub}:/usr/bin:/bin", "HOME": str(tmp_path)},
        capture_output=True,
        text=True,
        check=False,
    )
    assert done.returncode == 0, done.stderr
    if not log.exists():
        return []
    return [line.split() for line in log.read_text(encoding="utf-8").splitlines()]


def _tests() -> list[str]:
    test_dir = _REPO / "app" / "test"
    return sorted(
        p.relative_to(_REPO).as_posix() for p in test_dir.rglob("*_test.dart")
    )


def _one_run(runs: list[list[str]]) -> list[str]:
    """The files of the single flutter run, checked to be few and real."""
    assert len(runs) == 1
    assert runs[0][:4] == _HEAD
    files = runs[0][4:]
    assert 0 < len(files) <= _GATE_MAX
    assert all((_REPO / "app" / f).is_file() for f in files)
    return files


def test_a_deps_bump_runs_a_small_spread(run_script: Run, tmp_path: Path) -> None:
    """A pubspec.lock change no longer runs the whole suite."""
    files = _one_run(_runs(run_script, tmp_path, "app/pubspec.lock"))
    assert len(files) == _GATE_MAX


def test_all_files_stays_capped(run_script: Run, tmp_path: Path) -> None:
    """``pre-commit run --all-files`` passes every app file: still one small run."""
    lib = sorted(
        p.relative_to(_REPO).as_posix() for p in (_REPO / "app" / "lib").rglob("*.dart")
    )
    _one_run(_runs(run_script, tmp_path, "app/pubspec.yaml", *lib))


def test_a_changed_test_comes_first(run_script: Run, tmp_path: Path) -> None:
    """The commit's own test file is always in the run, first."""
    changed = _tests()[-1]
    files = _one_run(_runs(run_script, tmp_path, "app/pubspec.yaml", changed))
    assert files[0] == changed.removeprefix("app/")


def test_many_changed_tests_keep_the_first_six(run_script: Run, tmp_path: Path) -> None:
    """Eight changed tests: the first six, in the order given."""
    changed = _tests()[:8]
    files = _one_run(_runs(run_script, tmp_path, *changed))
    assert files == [f.removeprefix("app/") for f in changed[:_GATE_MAX]]


def test_no_app_files_run_nothing(run_script: Run, tmp_path: Path) -> None:
    """A commit outside app/ starts no flutter run."""
    assert _runs(run_script, tmp_path, "README.md") == []
