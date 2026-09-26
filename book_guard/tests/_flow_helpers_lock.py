# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Stand-ins for gatelock and the Tk view, so BookGuardLock runs headless.

gatelock's ``assert_not_under_pytest`` forbids a real lock window in tests;
every name ``book_guard._lock`` imports from gatelock and ``_lock_view`` is
swapped for a recording fake instead.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from types import SimpleNamespace
from typing import TYPE_CHECKING, Any

from book_guard import _lock

if TYPE_CHECKING:
    from collections.abc import Callable

    import pytest


class FakeVar:
    """A ``tk.StringVar`` that just holds its value."""

    def __init__(self, value: str = "") -> None:
        self.value = value

    def set(self, value: str) -> None:
        self.value = value

    def get(self) -> str:
        return self.value


class FakeField(FakeVar):
    """A Text/Entry: ``get`` ignores Tk indices; tracks focus and deletes."""

    focused = 0

    def get(self, *_index: str) -> str:
        return self.value

    def delete(self, *_index: str) -> None:
        self.value = ""

    def focus_force(self) -> None:
        self.focused += 1


@dataclass
class FakeInputs:
    summary: FakeField = field(default_factory=FakeField)
    escape: FakeField = field(default_factory=FakeField)


class FakeRoot:
    def __init__(self) -> None:
        self.titles: list[str] = []
        self.scheduled: list[tuple[int, Callable[[], None]]] = []

    def title(self, text: str) -> None:
        self.titles.append(text)

    def after(self, ms: int, callback: Callable[[], None]) -> None:
        self.scheduled.append((ms, callback))


class FakeJob:
    """OneJob without threads: work is stored, finishing is scripted."""

    def __init__(self) -> None:
        self.busy = False
        self.started: list[tuple[Callable[[], Any], Callable[[Any], None]]] = []
        self.finish: bool | Exception = False
        self.shut = False

    def start(self, work: Callable[[], Any], done: Callable[[Any], None]) -> bool:
        self.started.append((work, done))
        return True

    def finish_if_done(self) -> bool:
        if isinstance(self.finish, Exception):
            raise self.finish
        return self.finish

    def shutdown(self) -> None:
        self.shut = True


@dataclass
class LockFakes:
    """Everything the fakes saw, for assertions."""

    events: list[str] = field(default_factory=list)
    configs: list[Any] = field(default_factory=list)
    inputs: list[FakeInputs] = field(default_factory=list)
    demo_closes: list[Callable[[], None]] = field(default_factory=list)


def install_lock_fakes(monkeypatch: pytest.MonkeyPatch) -> LockFakes:
    """Swap every gatelock/Tk name ``book_guard._lock`` uses for a fake."""
    seen = LockFakes()

    class Arbiter:
        def __init__(self, name: str, rank: int, **kwargs: object) -> None:
            seen.events.append(f"arbiter {name} {rank} {sorted(kwargs.items())}")

        def publish(self) -> None:
            seen.events.append("publish")

        def acquire_holder(self) -> None:
            seen.events.append("acquire")

    class LockWindow:
        def __init__(self, _root: object, config: object, **_kw: object) -> None:
            seen.configs.append(config)

        def __getattr__(self, name: str) -> Callable[[], None]:
            return lambda: seen.events.append(f"window.{name}")

    def build_inputs(_column: object, _vars: object, **_callbacks: object) -> Any:
        seen.inputs.append(FakeInputs())
        return seen.inputs[-1]

    fakes = {
        "assert_not_under_pytest": lambda _what: None,
        "GateRoot": FakeRoot,
        "Arbiter": Arbiter,
        "LockWindow": LockWindow,
        "wait_for_turn": lambda _arbiter: seen.events.append("wait_for_turn"),
        "make_vars": lambda _root: SimpleNamespace(
            status=FakeVar(), todo=FakeVar(), quiz_title=FakeVar(), feedback=FakeVar()
        ),
        "build_status": lambda parent, _vars: parent,
        "build_inputs": build_inputs,
        "install_demo_close": lambda _parent, close: seen.demo_closes.append(close),
        "OneJob": FakeJob,
    }
    for name, fake in fakes.items():
        monkeypatch.setattr(_lock, name, fake)
    return seen
