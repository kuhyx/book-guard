# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Any day's requirement: past, today, future, and one simulated deviation.

Display only -- nothing here writes the ledger. The math is not forked: every
day is :func:`book_guard._pace.compute_pace` on an in-memory ledger copy.

* **past day** -- the requirement as it stood that morning: the ledger with
  every credit dated that day or later left out (the replay
  :func:`book_guard._bonus.day_requirement` already does);
* **today** -- live, from the ledger as it is;
* **future day** -- every day from today until then assumed to meet its
  requirement exactly: one forward walk appends a synthetic credit row per
  day (today: topped up to the requirement, never below what is credited);
* **sick day** -- asks nothing, so a future one is assumed to read 0 (a
  simulation can still add pages to it);
* **simulation** -- one ``±N`` deviation on a day from today on: that day's
  assumed pages are its baseline (the requirement, or today's credited pages
  when more) plus ``N``, never below 0, and every later day is recomputed by
  the usual surplus/debt rules.

A day before :data:`QUOTA_SWITCH_DATE` had no daily requirement
(:mod:`book_guard._pace_text` shows the old bonus rule instead). The app runs
a port of the same walk (``app/lib/src/pace_views.dart``) on
:mod:`book_guard._pace_inputs`; ``scripts/pace_goldens.py`` keeps them equal.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
import re
from typing import TYPE_CHECKING, Final

from book_guard._constants import PACE_START_DATE, QUOTA_SWITCH_DATE
from book_guard._ledger import CREDIT, Entry, Ledger
from book_guard._pace import compute_pace, month_start

if TYPE_CHECKING:
    from collections.abc import Callable, Iterable

    from book_guard._pace import Pace

PAST: Final = "past"
TODAY: Final = "today"
FUTURE: Final = "future"

_SIM: Final = re.compile(r"^([+-]?\d+)(?:@(\d{4}-\d{2}-\d{2}))?$")


@dataclass(frozen=True)
class Simulation:
    """One deviation: ``delta`` pages more (or fewer) than assumed on ``day``."""

    day: date
    delta: int


@dataclass(frozen=True)
class DayView:
    """One day's position, as it stood (past), stands (today) or would stand."""

    day: date
    kind: str
    """:data:`PAST`, :data:`TODAY` or :data:`FUTURE`."""
    pace: Pace
    """The month's pace computed for that day."""
    credited: int
    """Pages really credited that day (0 on a future day)."""
    assumed: int
    """Pages the projection counts that day: ``credited`` on a past day."""
    free: bool
    sick: bool
    simulated: int = 0
    """The simulation's ``delta`` when it falls on this day."""

    @property
    def required(self) -> int:
        """The day's requirement (its quota after moves plus weekend debt)."""
        return self.pace.ask.required

    @property
    def old_rule(self) -> bool:
        """Before the switch: no daily requirement, the old bonus rule."""
        return self.day < QUOTA_SWITCH_DATE

    @property
    def counted(self) -> bool:
        """A paced, non-free day: the line spreads over it."""
        return self.day >= PACE_START_DATE and not self.free


def parse_simulation(text: str, today: date) -> Simulation:
    """``-20@2026-10-16`` / ``+15`` / ``5`` as a :class:`Simulation`.

    The day defaults to ``today`` and may not be before it.

    Raises:
        ValueError: Not ``±N[@YYYY-MM-DD]``, or a day before today.
    """
    match = _SIM.match(text.strip())
    if match is None:
        msg = f"expected ±N[@YYYY-MM-DD], got {text!r}"
        raise ValueError(msg)
    day = date.fromisoformat(match[2]) if match[2] else today
    if day < today:
        msg = f"a simulation starts today or later, not {day}"
        raise ValueError(msg)
    return Simulation(day, int(match[1]))


def cached(is_free: Callable[[date], bool]) -> Callable[[date], bool]:
    """``is_free`` memoised: ``freedays`` reads its file on every call."""
    seen: dict[date, bool] = {}

    def check(day: date) -> bool:
        if day not in seen:
            seen[day] = is_free(day)
        return seen[day]

    return check


def _days(first: date, last: date) -> list[date]:
    return [first + timedelta(days=i) for i in range((last - first).days + 1)]


def _credited(ledger: Ledger, day: date) -> int:
    iso = day.isoformat()
    return sum(e.amount for e in ledger.of_kind(CREDIT) if e.day == iso)


def _before(ledger: Ledger, day: date) -> list[Entry]:
    """Every row except the credits dated ``day`` or later."""
    iso = day.isoformat()
    return [e for e in ledger.entries if not (e.kind == CREDIT and e.day >= iso)]


@dataclass(frozen=True)
class _Days:
    """Which days are free and which are sick, for every view of one call."""

    is_free: Callable[[date], bool]
    sick: frozenset[date]


def _past(ledger: Ledger, day: date, cal: _Days) -> DayView:
    pace = compute_pace(Ledger(_before(ledger, day)), day, cal.is_free, sick=cal.sick)
    pages = _credited(ledger, day)
    return DayView(day, PAST, pace, pages, pages, cal.is_free(day), day in cal.sick)


def _synthetic(day: date, amount: int) -> Entry:
    """An in-memory credit row: never signed, never written."""
    return Entry(f"projection:{day}", CREDIT, day.isoformat(), amount)


def _forward(
    ledger: Ledger,
    today: date,
    last: date,
    cal: _Days,
    sim: Simulation | None,
) -> Iterable[DayView]:
    """Today through ``last``, each day meeting its requirement (one walk)."""
    rows = _before(ledger, today + timedelta(days=1))
    for day in _days(today, last):
        pace = compute_pace(Ledger(rows), day, cal.is_free, sick=cal.sick)
        real = _credited(ledger, day) if day == today else 0
        assumed = max(real, pace.ask.required)
        delta = sim.delta if sim is not None and sim.day == day else 0
        assumed = max(assumed + delta, 0)
        if assumed != real:
            rows.append(_synthetic(day, assumed - real))
        kind = TODAY if day == today else FUTURE
        sick = day in cal.sick
        yield DayView(day, kind, pace, real, assumed, cal.is_free(day), sick, delta)


def views(
    ledger: Ledger,
    today: date,
    days: list[date],
    calendar: tuple[Callable[[date], bool], frozenset[date]],
    sim: Simulation | None = None,
) -> list[DayView]:
    """Each of ``days`` (ascending) as past, today or projected.

    ``calendar`` is ``(is_free, sick days)``.
    """
    is_free, sick = calendar
    cal = _Days(cached(is_free), sick)
    out = [_past(ledger, d, cal) for d in days if d < today]
    if days and days[-1] >= today:
        wanted = set(days)
        ahead = _forward(ledger, today, days[-1], cal, sim)
        out.extend(v for v in ahead if v.day in wanted)
    return out


def week_of(day: date) -> list[date]:
    """Mon-Sun around ``day``."""
    monday = day - timedelta(days=day.weekday())
    return _days(monday, monday + timedelta(days=6))


def month_of(day: date) -> list[date]:
    """Every day of ``day``'s month."""
    first = month_start(day)
    end = (first + timedelta(days=32)).replace(day=1)
    return _days(first, end - timedelta(days=1))
