# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The gate: lock the PC while the month's reading is behind the pace line.

gatelock owns the surfaces, the grab, VT switching and arbitration; this
module supplies the hooks and the loop that decides when to let go.

Slow work -- reading the inbox (a Claude vision call per photo) and grading
a summary -- runs on a worker thread, and the Tk thread only polls its
future. A Tk callback that blocked on a model call would freeze the lock
with the grab held, which on a hard lock is indistinguishable from a hang.
"""

from __future__ import annotations

import logging
from traceback import format_exc
from typing import TYPE_CHECKING, Final

from gatelock import (
    Arbiter,
    GateRoot,
    GrabPolicy,
    LockConfig,
    LockWindow,
    assert_not_under_pytest,
    wait_for_turn,
)

from book_guard import _ledger
from book_guard._actions import escape_today, process
from book_guard._claude import ClaudeUnavailableError
from book_guard._constants import POLL_INTERVAL_MS, RANK_BOOK_GUARD
from book_guard._grading import quiz_one
from book_guard._lock_view import (
    build_inputs,
    build_status,
    install_demo_close,
    make_vars,
)
from book_guard._morning import morning_skip_for
from book_guard._publish import write_next_file
from book_guard._render import status_lines, todo_lines
from book_guard._state import Snapshot, awaiting_quiz, snapshot
from book_guard._worker import OneJob

if TYPE_CHECKING:
    from datetime import date
    import tkinter as tk

    from gatelock import SurfaceInfo

    from book_guard._lock_view import PrimaryWidgets
    from book_guard._paths import Paths
    from book_guard._quiz import Verdict

_logger: Final = logging.getLogger(__name__)
_TICK_MS: Final = 500


def _ignore(_result: object) -> None:
    """The no-op completion for background work nobody waits on."""


class BookGuardLock:
    """A gatelock consumer that releases once reading is back on pace."""

    def __init__(self, paths: Paths, snap: Snapshot, *, production: bool) -> None:
        """Arm the lock. Demo mode (the default) uses a local grab."""
        assert_not_under_pytest("the book-guard lock")
        self._paths = paths
        self._snap = snap
        self._demo = not production
        self._closed = False
        self._inputs: dict[str, PrimaryWidgets] = {}
        self._worker = OneJob()
        self._config = LockConfig(
            mode="hard",
            overrideredirect=True,
            grab=GrabPolicy(
                kind="global" if production else "local", disable_vt=production
            ),
            app_name="book_guard",
            rank=RANK_BOOK_GUARD,
        )
        self.root = GateRoot()
        self.root.title("Book Guard" + ("" if production else " [DEMO]"))
        self._vars = make_vars(self.root)
        arbiter = Arbiter(
            "book_guard",
            RANK_BOOK_GUARD,
            grab=self._config.resolved_grab(),
            disable_vt=self._config.resolved_disable_vt(),
        )
        arbiter.publish()
        if production:
            wait_for_turn(arbiter)
        arbiter.acquire_holder()
        self._lock = LockWindow(self.root, self._config, hooks=self, arbiter=arbiter)
        self._lock.setup()
        self._render()
        self._lock.grab_input()
        self.root.after(POLL_INTERVAL_MS, self._poll)
        self.root.after(_TICK_MS, self._tick)

    # -- gatelock hooks ---------------------------------------------------

    def build_surface(self, parent: tk.Misc, surface: SurfaceInfo) -> None:
        """Paint one output; the input form goes on the primary one.

        Index 0 gets it too: an X server with no RandR primary (Xvfb, some
        single-monitor setups) would otherwise show a lock with no way to
        answer it.
        """
        column = build_status(parent, self._vars)
        if surface.is_primary or surface.index == 0:
            self._inputs[surface.output_name] = build_inputs(
                column, self._vars, on_submit=self._submit, on_escape=self._escape
            )
        if self._demo:
            install_demo_close(parent, self.close)

    def teardown_surface(self, surface: SurfaceInfo) -> None:
        """Forget the inputs if their output went away."""
        self._inputs.pop(surface.output_name, None)

    def on_focus_ready(self, surface: SurfaceInfo | None) -> None:
        """Focus the summary box once the lock is mapped."""
        widgets = self._inputs.get(surface.output_name) if surface else None
        if widgets is not None:
            widgets.summary.focus_force()

    def on_callback_error(self) -> None:
        """A Tk callback raised: say so and keep the lock up."""
        _logger.error("a Tk callback raised inside the lock:\n%s", format_exc())
        self._vars.feedback.set("Something went wrong -- still watching.")

    def on_close(self) -> None:
        """Every exit path: stop the worker without waiting on a model call."""
        self._worker.shutdown()

    # -- behaviour ----------------------------------------------------------

    def _render(self) -> None:
        snap = self._snap
        self._vars.status.set("\n".join(status_lines(snap, recent=4)[:4]))
        self._vars.todo.set(
            "\n".join(todo_lines(snap)) or "Go read, then upload photos."
        )
        pending = awaiting_quiz(snap)
        first = pending[0].session if pending else None
        self._vars.quiz_title.set(
            f"Summary for p. {first.start.page}-{first.end.page} (3-5 sentences):"
            if first
            else "No session is waiting for a summary."
        )

    def _tick(self) -> None:
        try:
            finished = self._worker.finish_if_done()
        except (ClaudeUnavailableError, OSError, ValueError) as exc:
            _logger.warning("background job failed inside the lock: %s", exc)
            self._vars.feedback.set(f"Could not finish: {exc}")
            finished = True
        if finished:
            self._refresh()
        if not self._closed:
            self.root.after(_TICK_MS, self._tick)

    def _refresh(self) -> None:
        self._snap = snapshot(self._paths, today=self._snap.today)
        write_next_file(self._paths, self._snap)
        if not self._snap.locked:
            _logger.info("released: %s", self._snap.reason)
            self.close()
            return
        self._render()

    def _poll(self) -> None:
        self._worker.start(lambda: process(self._paths, settle_wait=False), _ignore)
        if not self._closed:
            self.root.after(POLL_INTERVAL_MS, self._poll)

    def _typed(self, field: str) -> str:
        """The first non-empty text in ``field`` across the input forms."""
        for widgets in self._inputs.values():
            text = (
                widgets.summary.get("1.0", "end")
                if field == "summary"
                else widgets.escape.get()
            ).strip()
            if text:
                return text
        return ""

    def _submit(self) -> None:
        pending = awaiting_quiz(self._snap)
        text = self._typed("summary")
        if not pending or not text:
            return
        if self._worker.busy:
            self._vars.feedback.set(
                "Busy reading new photos -- submit again in a moment."
            )
            return
        self._vars.feedback.set("Grading...")

        def done(verdict: Verdict) -> None:
            prefix = "Passed. " if verdict.passed else "Not counted. "
            self._vars.feedback.set(prefix + verdict.feedback)
            for widgets in self._inputs.values():
                widgets.summary.delete("1.0", "end")

        self._worker.start(lambda: quiz_one(self._paths, pending[0], text), done)

    def _escape(self) -> None:
        error = escape_today(self._paths, self._typed("escape"))
        if error:
            self._vars.feedback.set(error)
            return
        self._refresh()

    def close(self) -> None:
        """Release the lock. Idempotent."""
        if not self._closed:
            self._closed = True
            self._lock.close()

    def run(self) -> None:
        """Hand control to Tk until the lock releases."""
        self._lock.run()


def run_gate(paths: Paths, *, production: bool, today: date | None = None) -> int:
    """Decide, and lock only when behind pace. Exit 0 either way."""
    if not _ledger.key_usable(paths.key_file):
        _logger.error("integrity key %s unreadable -- gate not armed", paths.key_file)
        return 0
    snap = snapshot(paths, today=today)
    write_next_file(paths, snap)
    if not snap.locked:
        _logger.info("not locking: %s", snap.reason)
        return 0
    if skip := morning_skip_for(paths, wait=production):
        _logger.warning("not locking yet: %s; %s", snap.reason, skip)
        return 0
    _logger.warning("locking: %s", snap.reason)
    BookGuardLock(paths, snap, production=production).run()
    return 0
