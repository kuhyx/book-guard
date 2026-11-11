# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""The demo photo renderer draws the check page the session now asks for."""

from __future__ import annotations

from datetime import datetime
import hashlib
from pathlib import Path
import zipfile

import pytest

from book_guard._photos import PhotoRecord
from book_guard._sessions import build_sessions, check_page_for
from scripts import demo_photos

_START = "2026-10-15T08:12:58+02:00"
_STOP = "2026-10-15T08:42:58+02:00"
_CHECK = "2026-10-15T08:45:00+02:00"


def _record(path: Path, page: int, iso: str) -> PhotoRecord:
    return PhotoRecord(
        sha=hashlib.sha256(path.read_bytes()).hexdigest(),
        name=path.name,
        taken_at=datetime.fromisoformat(iso).isoformat(),
        uploaded_at=iso,
        kind="page",
        page=page,
    )


def _epub(path: Path) -> Path:
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("c.xhtml", "<p>" + "treasure island " * 9000 + "</p>")
    return path


def test_check_photo_completes_the_demo_session(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    epub = _epub(tmp_path / "b.epub")
    out = tmp_path / "photos"
    assert demo_photos.main([str(epub), str(out), "40", _START, "62", _STOP]) == 0
    start, stop = sorted(Path(p) for p in capsys.readouterr().out.split())
    args = ["--check", str(epub), str(out), str(start), str(stop), _CHECK]
    assert demo_photos.main(args) == 0
    check = Path(capsys.readouterr().out.strip())
    records = [
        _record(start, 40, _START),
        _record(stop, 62, _STOP),
        _record(check, demo_photos.check_page(start, stop), _CHECK),
    ]
    (session,) = build_sessions(records)
    assert session.check is not None
    assert len(session.evidence) == 3
    assert session.check.page == check_page_for(records[0], records[1])


def test_check_page_refuses_a_stop_before_the_start(tmp_path: Path) -> None:
    early, late = tmp_path / "x_p5.jpg", tmp_path / "y_p9.jpg"
    early.write_bytes(b"a")
    late.write_bytes(b"b")
    with pytest.raises(ValueError, match="before the start"):
        demo_photos.check_page(late, early)


def test_check_page_needs_the_page_in_the_name(tmp_path: Path) -> None:
    plain = tmp_path / "plain.jpg"
    plain.write_bytes(b"a")
    with pytest.raises(ValueError, match="_p<page>"):
        demo_photos.check_page(plain, plain)
