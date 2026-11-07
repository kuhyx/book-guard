#!/usr/bin/env python3
# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Weekly re-check: has the latest onnxruntime shipped a cp315 wheel yet?

fastembed needs onnxruntime, which had no Python 3.15 wheel when CI moved to
"3.x", so pyproject skips fastembed on 3.15 and ``_embed`` raises there.
This asks PyPI once a week (``.github/workflows/onnxruntime-wheel.yml``).
No cp315 wheel: exit 0, nothing happens. A cp315 wheel: exit 1 and open one
GitHub issue (deduped by title) saying what to remove; the
``book-guard-wheel-todo`` user timer turns that issue into a todo-app task.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
from typing import TYPE_CHECKING, Any, Final
from urllib.request import urlopen

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence

    type Gh = Callable[[Sequence[str]], str]

PYPI_URL: Final = "https://pypi.org/pypi/onnxruntime/json"
TAG: Final = "cp315"
ISSUE_TITLE: Final = "onnxruntime ships a cp315 wheel: unpin fastembed on 3.15"
ISSUE_BODY: Final = (
    "onnxruntime {version} ships a {tag} wheel, so fastembed installs on "
    "Python 3.15: drop the marker in `pyproject.toml` and the guard in "
    "`_embed.py` (plus this check and its workflow and user timer)."
)


def wheel_tags(data: dict[str, Any]) -> set[str]:
    """The interpreter tags of the wheels in a PyPI JSON answer."""
    names = (str(f["filename"]) for f in data["urls"])
    return {name.split("-")[2] for name in names if name.endswith(".whl")}


def _gh(args: Sequence[str]) -> str:
    """Run the GitHub CLI and return its stdout."""
    binary = shutil.which("gh")
    if binary is None:
        msg = "no gh on PATH: cannot open the unpin issue"
        raise RuntimeError(msg)
    done = subprocess.run(
        [binary, *args], check=True, capture_output=True, text=True, timeout=60
    )
    return done.stdout


def open_issue(version: str, gh: Gh) -> bool:
    """Open the unpin issue unless one is open; True when it opened one."""
    listed = gh(
        [
            "issue",
            "list",
            "--state",
            "open",
            "--search",
            f'in:title "{ISSUE_TITLE}"',
            "--json",
            "title",
        ]
    )
    if any(i["title"] == ISSUE_TITLE for i in json.loads(listed or "[]")):
        return False
    body = ISSUE_BODY.format(version=version, tag=TAG)
    gh(["issue", "create", "--title", ISSUE_TITLE, "--body", body])
    return True


def run(data: dict[str, Any], gh: Gh) -> int:
    """Check one PyPI answer; 1 (and the issue) when the wheel is out."""
    version = str(data["info"]["version"])
    if TAG not in wheel_tags(data):
        sys.stdout.write(f"onnxruntime {version}: no {TAG} wheel yet\n")
        return 0
    opened = open_issue(version, gh)
    sys.stdout.write(
        f"onnxruntime {version} ships a {TAG} wheel: "
        + ("opened the unpin issue\n" if opened else "the unpin issue is open\n")
    )
    return 1


def _fetch() -> dict[str, Any]:
    """The latest onnxruntime release as PyPI's JSON API describes it."""
    with urlopen(PYPI_URL, timeout=30) as reply:  # constant https URL
        answer: dict[str, Any] = json.load(reply)
    return answer


def main(argv: Sequence[str] | None = None) -> int:
    """Parse ``argv``, read PyPI (or a stubbed answer) and check it."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pypi-json", type=Path, help="a stubbed PyPI answer")
    args = parser.parse_args(argv)
    if args.pypi_json is None:
        data = _fetch()
    else:
        data = json.loads(args.pypi_json.read_text(encoding="utf-8"))
    return run(data, _gh)


if __name__ == "__main__":
    sys.exit(main())
