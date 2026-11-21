# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""A bare ``freedays/`` folder on ``sys.path`` must not hide the real shared lib.

``python3 -m book_guard`` run from ``~/src/utils`` (or a site-packages left
with an empty ``freedays/`` mid-reinstall) made ``import freedays`` bind an
empty namespace package: ``freedays.is_free_day`` was missing.
"""

from __future__ import annotations

import sys
import types
from typing import TYPE_CHECKING

import pytest

from book_guard import _shared_libs

if TYPE_CHECKING:
    from pathlib import Path


def _fake_lib(root: Path, name: str) -> None:
    pkg = root / name
    pkg.mkdir(parents=True)
    (pkg / "__init__.py").write_text("REAL = True\n", encoding="utf-8")


def test_healthy_lib_is_left_alone(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """No shadow: nothing is imported, ``sys.path`` stays as it was."""
    _fake_lib(tmp_path / "site", "bg_lib")
    path = [str(tmp_path / "site")]
    monkeypatch.setattr(sys, "path", path)
    monkeypatch.delitem(sys.modules, "bg_lib", raising=False)
    _shared_libs.unshadow(("bg_lib", "bg_missing"))
    assert "bg_lib" not in sys.modules
    assert sys.path == path


def test_regular_package_beats_a_bare_folder(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """``PathFinder`` already prefers a real package to a bare cwd folder."""
    (tmp_path / "cwd" / "bg_lib").mkdir(parents=True)
    _fake_lib(tmp_path / "site", "bg_lib")
    monkeypatch.chdir(tmp_path / "cwd")
    path = ["", str(tmp_path / "site")]
    monkeypatch.setattr(sys, "path", path)
    monkeypatch.delitem(sys.modules, "bg_lib", raising=False)
    _shared_libs.unshadow(("bg_lib",))
    assert "bg_lib" not in sys.modules
    assert sys.path == path


def test_shadowed_namespace_already_imported_is_replaced(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An empty namespace module already in ``sys.modules`` is swapped out."""
    (tmp_path / "cwd" / "bg_lib").mkdir(parents=True)
    _fake_lib(tmp_path / "site", "bg_lib")
    monkeypatch.setattr(sys, "path", [str(tmp_path / "cwd"), str(tmp_path / "site")])
    hollow = types.ModuleType("bg_lib")
    hollow.__path__ = [str(tmp_path / "cwd" / "bg_lib")]
    monkeypatch.setitem(sys.modules, "bg_lib", hollow)
    _shared_libs.unshadow(("bg_lib",))
    assert sys.modules["bg_lib"].REAL is True


def test_real_module_already_imported_is_kept(monkeypatch: pytest.MonkeyPatch) -> None:
    """A module with a ``__file__`` is never touched."""
    real = types.ModuleType("bg_lib")
    real.__file__ = "/x/bg_lib/__init__.py"
    monkeypatch.setitem(sys.modules, "bg_lib", real)
    _shared_libs.unshadow(("bg_lib",))
    assert sys.modules["bg_lib"] is real


def test_meta_path_finder_supplies_the_real_lib(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An editable install's finder (after ``PathFinder``) is asked too."""
    (tmp_path / "site" / "bg_lib").mkdir(parents=True)
    _fake_lib(tmp_path / "src", "bg_lib")
    monkeypatch.setattr(sys, "path", [str(tmp_path / "site")])
    monkeypatch.delitem(sys.modules, "bg_lib", raising=False)

    class Editable:
        """Stands in for setuptools' ``__editable___*_finder``."""

        @staticmethod
        def find_spec(name: str, path: object, target: object = None) -> object:
            del path, target
            from importlib.machinery import PathFinder

            return PathFinder.find_spec(name, [str(tmp_path / "src")])

    no_find_spec = object()
    monkeypatch.setattr(sys, "meta_path", [*sys.meta_path, no_find_spec, Editable])
    _shared_libs.unshadow(("bg_lib",))
    assert sys.modules["bg_lib"].REAL is True


def test_no_real_lib_raises_a_clear_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Only bare folders: an ``ImportError`` naming them, not an AttributeError."""
    (tmp_path / "cwd" / "bg_lib").mkdir(parents=True)
    monkeypatch.setattr(sys, "path", [str(tmp_path / "cwd")])
    monkeypatch.delitem(sys.modules, "bg_lib", raising=False)
    with pytest.raises(ImportError, match=r"bg_lib.*cwd"):
        _shared_libs.unshadow(("bg_lib",))
    assert "bg_lib" not in sys.modules


def test_a_real_lib_that_fails_to_import_leaves_no_half_module(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The real lib's own error surfaces; ``sys.modules`` holds no stub."""
    hollow = types.ModuleType("bg_lib")
    hollow.__path__ = [str(tmp_path / "cwd" / "bg_lib")]
    broken = tmp_path / "site" / "bg_lib"
    broken.mkdir(parents=True)
    (broken / "__init__.py").write_text(
        "raise RuntimeError('boom')\n", encoding="utf-8"
    )
    monkeypatch.setattr(sys, "path", [str(tmp_path / "site")])
    monkeypatch.setitem(sys.modules, "bg_lib", hollow)
    with pytest.raises(RuntimeError, match="boom"):
        _shared_libs.unshadow(("bg_lib",))
    assert "bg_lib" not in sys.modules
