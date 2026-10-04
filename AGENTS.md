# book-guard -- notes for agents

Read README.md first. These are the invariants that are easy to break.

## Workflow

- Run the program before the tests: `BOOK_GUARD_ROOT=.demo python3 -m book_guard ...`
  is a full sandbox (its own ledger, photo cache and Reading folder); the
  real tree is `~/.local/share/book_guard` + `~/data/cloud/Reading`.
  `scripts/demo_photos.py` renders page photos with EXIF times from an epub;
  `process --now` (sandbox only) fakes the upload-check clock.
- Tests: `scripts/setup_dev.sh` once, then `.venv/bin/python -m pytest`
  (100% branch coverage is enforced). `book_guard/tests/conftest.py` makes
  every test hermetic -- extend it, never bypass it, when adding a path, a
  network call or a subprocess.
- `scripts/grader_suite.py [MODEL]` is the adversarial check of the local
  page reader and the grader on a real model (needs the sandbox demo
  session). Re-run it after touching `_quiz.py`, `_anchor.py` or the prompts.
- `scripts/page_truth.py` runs the page reader on real labelled photos
  (`~/data/book-guard_binaries/page_truth/manifest.json`) and exits 1 on a
  wrong number. Re-run after touching `_ocr.py`, `_pagenum.py` or
  `_reader.py`. The same manifest drives the app's on-device check:
  `adb push` it to `/sdcard/Android/data/com.kuhy.book_guard_app/files/page_truth/`,
  `touch .../run` (chmod 666), launch the app, read `page_truth {...}` lines
  from logcat (the app's own files are not adb-readable).
- Heavy commands run under `~/.claude/scripts/capped.sh`; indexing a book
  needs `CAP_MEM=4G`.

## Invariants

- **No model reads page numbers.** The phone (ML Kit) and the PC
  (Tesseract) do, upright by content, chosen by plausibility; ambiguous is
  a rejection that asks for a box, never a guess. A page photo must never
  wait on Claude.
- **The app is offline-first.** Every upload goes through its outbox; it
  must keep working (photos, page numbers, check page, summary queued) with
  the PC and the network both gone. App data lives in its support folder
  and survives `adb install -r` -- never uninstall or clear it.
- **Haiku only.** Every Claude call defaults to `DEFAULT_MODEL = "haiku"`;
  another model only via an explicit per-run `--model`. Never a config value.
- **Isolated Claude calls.** `_claude.ask` runs the CLI with
  `--setting-sources "" --tools "" --strict-mcp-config` from `cwd=/`, images
  as base64 blocks. Long free text goes after `---TEXT---`, never inside JSON.
- **The ledger is the only value-carrying state**, HMAC-signed with the shared
  `/etc/workout-locker/hmac.key`. screen-locker and steam-backlog-enforcer
  read `credit` rows with `detail.bonus == "1"`, dated by `detail.ended_at`.
  Changing that contract means changing both consumers in the same session.
- **Nothing credits without the grader** -- except a summary (150+ chars)
  whose grading has failed for `GRADER_GRACE` (1 h, outage or usage cap):
  `quiz_one` credits it with `detail.graded == "0"`. The MCP server and the
  app's request files are read-only / route through `_grading.quiz_one`.
- **A fail names what is missing** (1-3 topics, never the answers), and the
  one rewrite is judged only on those (`_prompt.py`). Re-run
  `scripts/grader_suite.py` after touching it.
- **One writer at a time**: every read-modify-write of the ledger or the
  photo cache happens inside `_flock.exclusive`.
- **EXIF capture time is the session clock**: DateTimeOriginal, falling back
  to IFD0 DateTime + OffsetTime (what the Android camera intent writes).
- **Never ship a penalty before its reward**: the 19:00 / 4h base cuts in the
  consumers are date-gated to `GATE_START_DATE`.

## Layout

- `book_guard/` -- the gate (CLI, lock, inbox, grading, index, MCP).
- `app/` -- the Flutter client (Android + web). Desktop = web build served by
  `bin/book_guard_desktop.dart` on :8773, which proxies `/dav` to dufs with
  the `bookguard` login. Never add a GTK `linux/` target.
- systemd user units at the repo root; `install.sh` installs them.

## Commands

Python gate at the root (`book_guard/`, venv from `scripts/setup_dev.sh`) plus
the Flutter client in `app/`. The gate runs as a live systemd daemon from this
tree: never restart it from a test run.

- run: `BOOK_GUARD_ROOT=.demo .venv/bin/python -m book_guard --help` | sandbox CLI; the daemon is the systemd units (`install.sh`)
- test: `.venv/bin/python -m pytest -q && (cd app && flutter test -j 1 --reporter=compact)`
- test-changed: `scripts/test_changed.sh`
- lint: `ruff check . && (cd app && flutter analyze --fatal-infos)`
- coverage: `.venv/bin/python -m pytest -q --cov-report=lcov:coverage.lcov`
- coverage-gaps: `coverage-gaps coverage.lcov`
