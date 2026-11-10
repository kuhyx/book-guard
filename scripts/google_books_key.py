# Copyright (c) 2026 Krzysztof Rudnicki. MIT License.
"""Install and verify the Google Books API key the ISBN lookup uses.

Without a key every Google Books call rides the anonymous quota that all
keyless callers share, and that runs dry daily (429). With a key of our own,
``_lookup._google`` reads ``data_dir/google_books_api_key`` and gets a
quota of its own.

    python -m scripts.google_books_key          # key from the clipboard
    python -m scripts.google_books_key --verify-only
    python -m scripts.google_books_key --open   # the console pages

Installing writes the key (mode 0600), clears the backoff an earlier 429
left on google-books, then verifies. Verifying asks Google directly, never
through the ISBN cache (a cached answer would pass without reaching Google):
exit 0 when a known book (the positive control) resolves with the key.
The key itself is never printed.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from typing import TYPE_CHECKING, Final

from book_guard._atomic_json import write_json
from book_guard._paths import _default
from book_guard._sources import google_books

if TYPE_CHECKING:
    from pathlib import Path

CONTROL_ISBN: Final = "9781784708283"  # 21 Lessons, Vintage paperback
# Enable the Books API, then create a key (restrict it to the Books API).
# authuser: kuhy-syncs lives on this account, not the browser default one.
_CONSOLE: Final = "https://console.cloud.google.com/apis"
_SCOPE: Final = "?project=kuhy-syncs&authuser=321krzychu@gmail.com"
CONSOLE_PAGES: Final = (
    f"{_CONSOLE}/library/books.googleapis.com{_SCOPE}",
    f"{_CONSOLE}/credentials{_SCOPE}",
)
_KEY_SHAPE: Final = re.compile(r"AIza[0-9A-Za-z_-]{35}")


def _clipboard() -> str:
    xclip = shutil.which("xclip")
    if xclip is None:
        sys.exit("xclip is not installed (pacman -S xclip)")
    return subprocess.run(
        [xclip, "-o", "-selection", "clipboard"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def _say(line: str) -> None:
    sys.stdout.write(line + "\n")


def _install(key_file: Path, sources: Path, key: str) -> None:
    if not _KEY_SHAPE.fullmatch(key):
        sys.exit("the clipboard does not hold a Google API key (AIza..., 39 chars)")
    tmp = key_file.with_suffix(".tmp")
    tmp.touch(mode=0o600)  # private before the key is in it
    tmp.chmod(0o600)
    tmp.write_text(key + "\n", encoding="utf-8")
    tmp.replace(key_file)
    if sources.exists():
        state = json.loads(sources.read_text(encoding="utf-8"))
        if isinstance(state, dict) and state.pop("google-books", None) is not None:
            write_json(sources, state, indent=1)
    _say(f"key written to {key_file}; google-books backoff cleared")


def _verify(key_file: Path, isbns: list[str]) -> int:
    if not key_file.is_file():
        _say(f"FAIL: no key at {key_file}")
        return 1
    key = key_file.read_text(encoding="utf-8").strip()
    control = google_books(CONTROL_ISBN, key)
    if control is None or not control.title:
        _say(f"FAIL: Google Books found nothing for control {CONTROL_ISBN}")
        return 1
    _say(f"OK: key works ({CONTROL_ISBN} -> {control.title}, {control.pages} p)")
    for isbn in isbns:
        info = google_books(isbn, key)
        _say(f"{isbn}: {info or 'Google Books does not know it'}")
    return 0


def main(argv: list[str] | None = None) -> int:
    """Install (unless ``--verify-only``) then verify; the exit code is the verdict."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument(
        "--open", action="store_true", help="only open the console pages"
    )
    parser.add_argument("isbn", nargs="*", help="also report what Google knows")
    args = parser.parse_args(argv)
    if args.open:
        opener = shutil.which("xdg-open")
        if opener is None:
            sys.exit("xdg-open is not installed (pacman -S xdg-utils)")
        for url in CONSOLE_PAGES:
            # xdg-open hands the URL to the browser and returns; its own
            # session keeps the browser alive after this script exits.
            subprocess.run(
                [opener, url],
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        return 0
    paths = _default()
    if not args.verify_only:
        _install(paths.google_key_file, paths.lookup_sources, _clipboard())
    return _verify(paths.google_key_file, args.isbn)


if __name__ == "__main__":
    sys.exit(main())
