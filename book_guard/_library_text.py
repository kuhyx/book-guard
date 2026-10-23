# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""``book-guard library``: the library document as lines, or as Markdown."""

from __future__ import annotations

from typing import Any

_STATUS = {
    "finished": "finished",
    "reading": "in progress",
    "not-started": "not started",
}


def _day(iso: str | None) -> str:
    return iso[:10] if iso else "-"


def _pages(book: dict[str, Any]) -> str:
    last = book["last_page_read"] or 0
    return f"p. {last}/{book['pages'] or '?'}, {book['pages_read']} pages credited"


def book_line(book: dict[str, Any]) -> str:
    """One book, one line: status, pages, dates, counts."""
    when = (
        f"finished {_day(book['finished_at'])}"
        if book["finished_at"]
        else f"read {_day(book['first_read_at'])} .. {_day(book['last_read_at'])}"
    )
    mark = "*" if book["current"] else " "
    return (
        f"{mark} {book['isbn']}  {book['title']}"
        + (f" -- {book['author']}" if book["author"] else "")
        + f"  [{_STATUS[book['status']]}] {_pages(book)}; {when}; "
        f"{len(book['sessions'])} sessions, {len(book['notes'])} notes"
    )


def library_lines(doc: dict[str, Any]) -> list[str]:
    """Every book, current first (``*``)."""
    return [book_line(b) for b in doc["books"]] or ["No books registered yet."]


def _attempt_lines(attempt: dict[str, Any], indent: str) -> list[str]:
    verdict = "passed" if attempt["passed"] else "failed"
    who = attempt["grader"] or ("ungraded" if not attempt["graded"] else "?")
    number = attempt["id"].partition("#")[2] or "1"
    return [
        f"{indent}{number}. {verdict} ({who})",
        f"{indent}  summary: {attempt['summary'] or '-'}",
        f"{indent}  grader: {attempt['feedback'] or '-'}",
    ]


def _session_head(s: dict[str, Any]) -> str:
    return (
        f"{_day(s['ended_at'])}  {'≈ ' if s.get('estimated') else ''}"
        f"p. {s['start_page']}-{s['end_page']} "
        f"({s['pages']} p, {s['minutes']} min) {s['status']}"
    )


def _note_head(note: dict[str, Any]) -> str:
    where = ", ".join(
        part
        for part in (
            f"p. {note['page']}" if note.get("page") else "",
            note.get("chapter", ""),
        )
        if part
    )
    return f"{_day(note.get('updated_at'))}" + (f" ({where})" if where else "")


def book_detail(book: dict[str, Any]) -> list[str]:
    """``--isbn``: chapters, sessions with every attempt, notes."""
    lines = [book_line(book).strip(), "", "Chapters:"]
    lines += [f"  p. {c['start']}: {c['title']}" for c in book["chapters"]] or ["  -"]
    lines += ["", "Sessions:"]
    for s in book["sessions"]:
        lines.append(f"  {_session_head(s)}")
        for attempt in s["attempts"]:
            lines += _attempt_lines(attempt, "    ")
    lines += [] if book["sessions"] else ["  -"]
    lines += ["", "Notes:"]
    lines += [f"  {_note_head(n)}: {n['text']}" for n in book["notes"]] or ["  -"]
    return lines


def _md_book(book: dict[str, Any]) -> list[str]:
    head = f"## {book['title']}" + (f" -- {book['author']}" if book["author"] else "")
    lines = [
        head,
        "",
        f"- ISBN {book['isbn']}, {_STATUS[book['status']]}, {_pages(book)}",
        (
            f"- first read {_day(book['first_read_at'])}, last read "
            f"{_day(book['last_read_at'])}, finished {_day(book['finished_at'])}"
        ),
        "",
    ]
    if book["chapters"]:
        lines += ["### Chapters", ""]
        lines += [f"- p. {c['start']}: {c['title']}" for c in book["chapters"]] + [""]
    if book["notes"]:
        lines += ["### Notes", ""]
        lines += [f"- **{_note_head(n)}**: {n['text']}" for n in book["notes"]] + [""]
    if book["sessions"]:
        lines += ["### Sessions", ""]
    for s in book["sessions"]:
        lines += [f"#### {_session_head(s)}", ""]
        final = s["attempts"][-1] if s["attempts"] else None
        if final:
            lines += [final["summary"] or "_no summary_", ""]
            lines += [f"> Grader ({final['grader'] or '-'}): {final['feedback']}", ""]
    return lines


def markdown(doc: dict[str, Any]) -> str:
    """The whole library (or the books given) as one Markdown document."""
    lines = ["# Reading library", ""]
    for book in doc["books"]:
        lines += _md_book(book)
    return "\n".join(lines).rstrip() + "\n"
