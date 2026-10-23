# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Sessions read in the app: recorded from the app's request, kept forever.

The app's reader taps Start (offset + wall-clock time, kept on the phone)
and Stop, then queues one ``ebook_session`` request through its outbox:

    {"session": "<app id>", "isbn": str, "start_offset": int,
     "end_offset": int, "started_at": iso, "ended_at": iso, "text_sha": str}

The PC checks it, estimates its physical pages with its own page map (the
copy on the share is never trusted) and appends it to
``data_dir/ebook_sessions.json`` -- append-only, like everything else that
records reading. From then on it is a :class:`~book_guard._sessions.Session`
like any photo pair: too fast below 50 s a page, else waiting for its
summary, graded on the exact text that was on screen, credited through
``_quiz.record_verdict`` and the bonus rule.

Time is plain wall-clock between the two taps: the app may be closed or
killed in between. What is refused (nothing is stored): a session over
:data:`MAX_SESSION`, one that ended in the future or more than
:data:`MAX_UPLOAD_DELAY` ago, less than a page, a text the PC no longer
serves, and any overlap -- with another in-app session, a paper session
(nobody reads the paper copy and the app at once; that would credit the
same hour twice). A paper session formed later across an in-app session
is the one that does not count (``_state.OVERLAP``).
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, fields
from datetime import UTC, datetime, timedelta
import hashlib
import json
import logging
import re
from typing import TYPE_CHECKING, Any, Final

from book_guard._atomic_json import write_json
from book_guard._constants import MAX_SESSION, MAX_UPLOAD_DELAY
from book_guard._ebook import load_map
from book_guard._ebook_overlap import overlaps, paper_conflict
from book_guard._flock import exclusive
from book_guard._photos import PhotoRecord
from book_guard._requests import Response
from book_guard._sessions import EbookSpan, Session

if TYPE_CHECKING:
    from book_guard._paths import Paths

_logger: Final = logging.getLogger(__name__)

EBOOK_KIND: Final = "ebook"
"""The ``kind`` of an in-app session's start/end record: never a photo."""
_KEY: Final = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
_CLOCK_SKEW: Final = timedelta(minutes=5)


@dataclass(frozen=True)
class EbookRead:
    """One stored in-app session, as checked when it arrived."""

    session: str
    isbn: str
    start_offset: int
    end_offset: int
    start_page: int
    end_page: int
    """The first page *not* read, like a stop photo's page."""
    started_at: str
    ended_at: str
    text_sha: str
    received_at: str

    def _record(self, role: str, page: int, at: str) -> PhotoRecord:
        name = f"ebook-{self.session}-{role}"
        return PhotoRecord(
            sha=hashlib.sha256(name.encode()).hexdigest(),
            name=name,
            taken_at=at,
            uploaded_at=self.received_at,
            kind=EBOOK_KIND,
            page=page,
        )

    def to_session(self) -> Session:
        """The session every surface lists, grades and credits."""
        return Session(
            start=self._record("start", self.start_page, self.started_at),
            end=self._record("end", self.end_page, self.ended_at),
            check_page=None,
            ebook=EbookSpan(
                self.session, self.isbn, self.start_offset, self.end_offset
            ),
        )


def load(paths: Paths) -> list[EbookRead]:
    """Every stored in-app session, oldest first; a missing file is none."""
    if not paths.ebook_sessions.exists():
        return []
    raw = json.loads(paths.ebook_sessions.read_text(encoding="utf-8"))
    known = {f.name for f in fields(EbookRead)}
    return [
        EbookRead(**{k: v for k, v in row.items() if k in known})
        for row in raw["sessions"]
    ]


def sessions(paths: Paths) -> list[Session]:
    """The stored in-app sessions as :class:`Session` objects."""
    return [read.to_session() for read in load(paths)]


def _when(raw: object) -> datetime | None:
    try:
        moment = datetime.fromisoformat(str(raw))
    except ValueError as exc:
        _logger.warning("in-app session time %r refused (%s)", raw, exc)
        return None
    return moment if moment.tzinfo is not None else None


def _offset(raw: object) -> int | None:
    return raw if isinstance(raw, int) and not isinstance(raw, bool) else None


type Stretch = tuple[int, int, datetime, datetime]
"""Start and end offset, Start and Stop tap."""


def _stretch(request: dict[str, Any], chars: int, now: datetime) -> Stretch | str:
    """The offsets and the taps, or why they cannot count."""
    a, b = _offset(request.get("start_offset")), _offset(request.get("end_offset"))
    if a is None or b is None or not 0 <= a < b <= chars:
        return "The start and end offsets do not fit the book text."
    started, ended = _when(request.get("started_at")), _when(request.get("ended_at"))
    if started is None or ended is None or ended <= started:
        return "The start and end times are not valid."
    if ended - started > MAX_SESSION:
        return "More than 6 h between Start and Stop: not counted. Start again."
    if ended > now + _CLOCK_SKEW:
        return "The session ends in the future: check the phone's clock."
    if now - ended > MAX_UPLOAD_DELAY:
        return "The session ended more than 7 days ago: too late to count."
    return a, b, started, ended


def _checked(paths: Paths, request: dict[str, Any], now: datetime) -> EbookRead | str:
    """The session to store, or why it cannot count."""
    key = str(request.get("session", ""))
    if not _KEY.fullmatch(key):
        return "Not a valid session id."
    isbn = str(request.get("isbn", ""))
    found = load_map(paths, isbn)
    if found is None:
        return f"There is no page map for ISBN {isbn} on the PC (yet)."
    if request.get("text_sha") != found.text_sha:
        return "The book text changed since the app downloaded it: reopen the reader."
    stretch = _stretch(request, found.chars, now)
    if isinstance(stretch, str):
        return stretch
    a, b, started, ended = stretch
    first, stop = found.pages.page_at(a), found.pages.page_at(b)
    if stop <= first:
        return "That is less than a page: nothing to credit."
    return EbookRead(
        session=key,
        isbn=isbn,
        start_offset=a,
        end_offset=b,
        start_page=first,
        end_page=stop,
        started_at=started.isoformat(),
        ended_at=ended.isoformat(),
        text_sha=found.text_sha,
        received_at=now.isoformat(),
    )


def record(paths: Paths, request: dict[str, Any]) -> Response:
    """The ``ebook_session`` request: store the session, or say why not."""
    checked = _checked(paths, request, datetime.now(tz=UTC))
    if isinstance(checked, str):
        _logger.info("in-app session refused: %s", checked)
        return Response(ok=False, message=checked)
    span = (
        datetime.fromisoformat(checked.started_at),
        datetime.fromisoformat(checked.ended_at),
    )
    with exclusive(paths):
        stored = load(paths)
        if any(r.session == checked.session for r in stored):
            return Response(
                ok=True, message="This in-app session was already recorded."
            )
        for other in stored:
            theirs = (
                datetime.fromisoformat(other.started_at),
                datetime.fromisoformat(other.ended_at),
            )
            if overlaps(span, theirs):
                return Response(
                    ok=False,
                    message="It overlaps another in-app session: one at a time.",
                )
        starts = [datetime.fromisoformat(r.started_at) for r in stored]
        conflict = paper_conflict(paths, span, starts)
        if conflict is not None:
            return Response(ok=False, message=conflict)
        rows = [asdict(r) for r in [*stored, checked]]
        write_json(paths.ebook_sessions, {"sessions": rows}, indent=1)
    pages = checked.end_page - checked.start_page
    return Response(
        ok=True,
        message=(
            f"Read in the app: ≈ p. {checked.start_page}-{checked.end_page}"
            f" ({pages} pages). Write its summary to have it credited."
        ),
        data={
            "session_id": checked.to_session().session_id,
            "start_page": checked.start_page,
            "end_page": checked.end_page,
            "pages": pages,
        },
    )
