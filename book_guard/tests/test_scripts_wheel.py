# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The weekly onnxruntime cp315 re-check and its issue -> todo-task sync."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import TYPE_CHECKING, Any

from scripts import check_onnxruntime_wheel as wheel

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence
    import subprocess

    import pytest

    type Run = Callable[..., subprocess.CompletedProcess[str]]

REPO = Path(__file__).resolve().parents[2]
SYNC = REPO / "scripts" / "sync_wheel_issue_to_todo.sh"


def pypi(version: str, tags: Sequence[str]) -> dict[str, Any]:
    """A PyPI JSON answer for ``version`` with one wheel per tag."""
    urls = [
        {"filename": f"onnxruntime-{version}-{t}-{t}-manylinux_2_28_x86_64.whl"}
        for t in tags
    ]
    urls.append({"filename": f"onnxruntime-{version}.tar.gz"})
    return {"info": {"version": version}, "urls": urls}


class FakeGh:
    """Records gh calls; ``open_titles`` are the open issues it lists."""

    def __init__(self, open_titles: Sequence[str] = ()) -> None:
        self.open_titles = list(open_titles)
        self.calls: list[list[str]] = []

    def __call__(self, args: Sequence[str]) -> str:
        self.calls.append(list(args))
        if args[:2] == ["issue", "list"]:
            return json.dumps([{"title": t} for t in self.open_titles])
        if args[:2] == ["issue", "create"]:
            self.open_titles.append(args[args.index("--title") + 1])
        return ""


def test_wheel_tags_ignore_the_sdist() -> None:
    assert wheel.wheel_tags(pypi("1.31.1", ["cp313", "cp314"])) == {"cp313", "cp314"}


def test_no_cp315_passes_and_opens_nothing(capsys: pytest.CaptureFixture[str]) -> None:
    gh = FakeGh()
    code = wheel.run(pypi("1.31.1", ["cp313", "cp314"]), gh)
    assert code == 0
    assert gh.calls == []
    assert "onnxruntime 1.31.1: no cp315 wheel yet" in capsys.readouterr().out


def test_a_cp315_wheel_fails_and_opens_one_issue() -> None:
    gh = FakeGh()
    data = pypi("1.32.0", ["cp314", "cp315"])
    assert wheel.run(data, gh) == 1
    creates = [c for c in gh.calls if c[:2] == ["issue", "create"]]
    assert len(creates) == 1
    body = creates[0][creates[0].index("--body") + 1]
    assert "drop the marker in `pyproject.toml` and the guard in `_embed.py`" in body
    assert creates[0][creates[0].index("--title") + 1] == wheel.ISSUE_TITLE
    # A second run with the issue still open fails again but adds nothing.
    assert wheel.run(data, gh) == 1
    assert len([c for c in gh.calls if c[:2] == ["issue", "create"]]) == 1


def test_main_reads_a_stubbed_answer(tmp_path: Path) -> None:
    answer = tmp_path / "pypi.json"
    answer.write_text(json.dumps(pypi("1.31.1", ["cp314"])), encoding="utf-8")
    assert wheel.main(["--pypi-json", str(answer)]) == 0


# -- the user timer's sync: open issue -> one todo task ------------------------


def stub(folder: Path, name: str, body: str) -> None:
    """An executable ``name`` in ``folder`` running ``body``."""
    path = folder / name
    path.write_text(f"#!/bin/bash\nset -euo pipefail\n{body}\n", encoding="utf-8")
    path.chmod(0o755)


def run_sync(
    run_script: Run,
    tmp_path: Path,
    *,
    issue_open: bool,
    live_ids: str = "",
    done_ids: str = "",
) -> list[str]:
    """Run the sync with stub gh + todo CLI; returns the notes ever added."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    notes = tmp_path / "notes.txt"
    notes.touch()
    titles = json.dumps([wheel.ISSUE_TITLE] if issue_open else [])
    stub(bin_dir, "gh", f"printf '%s\\n' '{titles}' | jq -r '.[]'")
    stub(
        bin_dir,
        "todo",
        f"""
case "$1" in
  --search) grep -F -- "$2" {notes} | sed 's/^/abcdef12\\ttodo\\tmedium\\tkuhyx\\/book-guard\\t/' || true ;;
  --get)
    if [[ " {live_ids} " == *" $2 "* ]]; then printf 'id: %s\\nstatus: todo\\n' "$2"
    elif [[ " {done_ids} " == *" $2 "* ]]; then printf 'id: %s\\nstatus: done\\n' "$2"
    else exit 1; fi ;;
  --text) printf '%s\\n' "$2" | head -1 >> {notes} ;;
  *) exit 64 ;;
esac""",
    )
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}
    env["BOOK_GUARD_TODO_CLI"] = str(bin_dir / "todo")
    run_script(["bash", str(SYNC)], check=True, env=env, timeout=20)
    return notes.read_text(encoding="utf-8").splitlines()


def test_sync_adds_one_task_and_dedupes_by_title(
    run_script: Run, tmp_path: Path
) -> None:
    assert run_sync(run_script, tmp_path, issue_open=True) == [wheel.ISSUE_TITLE]
    assert run_sync(run_script, tmp_path, issue_open=True) == [wheel.ISSUE_TITLE]


def test_sync_without_an_open_issue_adds_nothing(
    run_script: Run, tmp_path: Path
) -> None:
    assert run_sync(run_script, tmp_path, issue_open=False) == []


def test_sync_reuses_the_open_unpin_task(run_script: Run, tmp_path: Path) -> None:
    got = run_sync(run_script, tmp_path, issue_open=True, live_ids="0ea3306e")
    assert got == []


def test_sync_adds_the_task_once_the_unpin_task_is_closed(
    run_script: Run, tmp_path: Path
) -> None:
    # `todo --get` finds a closed note too: only an open one is reused.
    got = run_sync(run_script, tmp_path, issue_open=True, done_ids="0ea3306e")
    assert got == [wheel.ISSUE_TITLE]


def test_sync_title_matches_the_check() -> None:
    assert f'readonly TITLE="{wheel.ISSUE_TITLE}"' in SYNC.read_text(encoding="utf-8")
