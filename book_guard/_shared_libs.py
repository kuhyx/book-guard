# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Keep a bare folder on ``sys.path`` from hiding a shared lib.

The shared libs (``freedays``, ``sickdays``, ...) are editable installs: their
finder sits *after* ``PathFinder`` in ``sys.meta_path``. So any ``sys.path``
entry holding a plain ``freedays/`` folder -- the cwd when run from
``~/src/utils``, or a site-packages left with an empty one mid-reinstall --
wins as an empty namespace package, and ``freedays.is_free_day`` is missing.

``unshadow`` runs once from ``book_guard/__init__``. A healthy lib costs one
``find_spec`` and is not imported; a shadowed one is loaded from its real
spec, so every later ``import freedays`` gets it. ``sys.path`` is not changed.
"""

from __future__ import annotations

from importlib.machinery import ModuleSpec, PathFinder
import importlib.util
from pathlib import Path
import sys
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from importlib.abc import Loader

SHARED_LIBS = ("freedays", "sickdays", "gatelock", "focus_project")


def _is_real(spec: object) -> bool:
    """A loadable module or package: not a namespace portion."""
    return (
        isinstance(spec, ModuleSpec)
        and spec.origin is not None
        and spec.loader is not None
    )


def _real_spec(name: str) -> ModuleSpec | None:
    """The spec of a real module or package, skipping namespace portions."""
    for finder in sys.meta_path:
        find = getattr(finder, "find_spec", None)
        if find is None or finder is PathFinder:
            continue
        spec = find(name, None)
        if _is_real(spec):
            return cast("ModuleSpec", spec)
    return None


def _shadow_dirs(name: str) -> list[str] | None:
    """The bare folders hiding ``name``, or ``None`` when it is healthy."""
    loaded = sys.modules.get(name)
    if loaded is not None:
        if getattr(loaded, "__file__", None) is not None:
            return None
        return list(loaded.__path__)
    spec = importlib.util.find_spec(name)
    if spec is None or _is_real(spec):
        return None
    return list(spec.submodule_search_locations or ())


def _load(name: str, spec: ModuleSpec) -> None:
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    try:
        # _is_real vouched for the loader of every spec that reaches here.
        cast("Loader", spec.loader).exec_module(module)
    except BaseException:
        del sys.modules[name]
        raise


def unshadow(names: tuple[str, ...] = SHARED_LIBS) -> None:
    """Load the real module for every shared lib a bare folder hides."""
    for name in names:
        shadows = _shadow_dirs(name)
        if shadows is None:
            continue
        sys.modules.pop(name, None)
        parents = {str(Path(d).parent) for d in shadows}
        rest = [p for p in sys.path if str(Path(p).resolve()) not in parents]
        spec = PathFinder.find_spec(name, rest)
        if not _is_real(spec):
            spec = _real_spec(name)
        if spec is None:
            msg = f"{name} is hidden by bare folder(s) {shadows}; run elsewhere"
            raise ImportError(msg, name=name)
        _load(name, spec)
