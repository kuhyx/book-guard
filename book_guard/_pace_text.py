# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``book-guard ask`` as text: one day in full, or a row per day.

A day before :data:`QUOTA_SWITCH_DATE` had no daily requirement: it shows
the old bonus rule and the pages credited that day (Q16).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Final

from book_guard._constants import (
    BONUS_MIN_MINUTES,
    BONUS_MIN_PAGES,
    PACE_BONUS_MIN_MINUTES,
    PACE_BONUS_MIN_PAGES,
    PACE_START_DATE,
)
from book_guard._pace_view import FUTURE, PAST, TODAY

if TYPE_CHECKING:
    from book_guard._pace_view import DayView

OLD_RULE: Final = (
    f"Old rule: {BONUS_MIN_PAGES} pages + {BONUS_MIN_MINUTES} min "
    f"({PACE_BONUS_MIN_PAGES} + {PACE_BONUS_MIN_MINUTES} when on pace)"
)
"""What a day before :data:`QUOTA_SWITCH_DATE` asked (Q16)."""


def _assumed_note(view: DayView) -> str:
    if view.simulated:
        return f" (simulated: {view.assumed} read, {view.simulated:+d})"
    if view.kind == FUTURE:
        return f" (assumed {view.assumed} read)"
    if view.kind == TODAY and view.assumed != view.credited:
        return f" (projection assumes {view.assumed})"
    return ""


def row(view: DayView) -> str:
    """One line for the week/month listings."""
    head = f"{view.day:%a %Y-%m-%d}  {view.kind:<6}"
    if view.day < PACE_START_DATE:
        return f"{head}  no quota yet, read {view.credited}"
    if view.free:
        return f"{head}  free day, read {view.credited}{_assumed_note(view)}"
    if view.sick:
        return f"{head}  sick day, read {view.credited}{_assumed_note(view)}"
    if view.old_rule:
        return f"{head}  old rule (15+15 / 10+10), read {view.credited}"
    met = "  met" if view.kind != FUTURE and view.credited >= view.required else ""
    read = "" if view.kind == FUTURE else f"  read {view.credited:>3}"
    return f"{head}  needs {view.required:>3}{read}{met}{_assumed_note(view)}"


def detail(view: DayView) -> list[str]:
    """Everything about one day."""
    when = {
        PAST: "as it stood that morning",
        TODAY: "live",
        FUTURE: "projected: every day before it meets its requirement",
    }[view.kind]
    lines = [f"{view.day:%a %Y-%m-%d} ({view.kind}, {when})"]
    p = view.pace
    if view.day < PACE_START_DATE:
        return [*lines, f"  no page quota before {PACE_START_DATE}"]
    if view.old_rule:
        return [*lines, f"  {OLD_RULE}; credited that day: {view.credited} pages"]
    if view.free:
        lines.append("  free day: asks nothing")
    elif view.sick:
        lines.append(
            "  sick day: asks nothing, its share moves to the days left "
            f"(reading {view.pace.ask.bonus_at} pages still earns the +1h)"
        )
    else:
        got = "" if view.kind == FUTURE else f"; credited {view.credited}"
        lines.append(f"  requirement: {view.required} pages{got}{_assumed_note(view)}")
    behind = f" ({p.behind} behind)" if p.behind else " (on pace)"
    lines.append(
        f"  {p.month:%B %Y}: target {p.target}, line at the start of the day "
        f"{p.required}, read {p.pages}{behind}"
    )
    if p.carried_debt or p.carried_credit:
        lines.append(
            f"  carried from earlier months: debt {p.carried_debt}, "
            f"credit {p.carried_credit}"
        )
    a = p.ask
    if a.debt_per_day or a.debt_unplaced:
        lines.append(
            f"  debt: up to {a.debt_per_day}/day over {a.debt_days} weekend days"
            f"; {a.debt_unplaced} carried into next month"
        )
    return lines
