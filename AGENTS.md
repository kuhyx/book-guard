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
- `scripts/pace_goldens.py` writes `app/test/fixtures/pace_goldens.json`,
  the answers the app's Dart port of the plan must match. Re-run it after
  touching `_quotas.py`, `_plan.py`, `_pace*.py` or `_ask.py`, and commit
  the fixture with the change (`test_pace_goldens_are_current` fails on a
  stale one).
- Heavy commands run under `~/.claude/scripts/capped.sh`; indexing a book
  needs `CAP_MEM=4G`.

## Invariants

- **No model reads page numbers, and the phone's number is trusted.** The
  phone (ML Kit) reads it upright by content and the reader confirms or
  boxes it there; the PC takes that number as is -- no Tesseract re-read,
  no plausibility check, no "unclear". Tesseract is only the fallback for a
  photo that arrives with no number (desktop web upload, "Send anyway"):
  chosen by plausibility, ambiguous is a rejection that asks for a box,
  never a guess. A page photo must never wait on Claude.
- **The app is offline-first.** Every upload goes through its outbox; it
  must keep working (photos, page numbers, check page, summary queued) with
  the PC and the network both gone. App data lives in its support folder
  and survives `adb install -r` -- never uninstall or clear it.
- **Haiku only, then local.** Every Claude call defaults to
  `DEFAULT_MODEL = "haiku"`; another model only via an explicit per-run
  `--model`. Never a config value. Only when Claude fails (outage, usage
  cap) does the fallback in `_local.py` (ollama) answer: `LOCAL_MODEL`
  (`qwen3:32b`) re-casts *all* grading votes, `LOCAL_VISION_MODEL` reads a
  contents photo -- constants too. The local grader gets `LOCAL_REMINDER`
  appended; Haiku's prompt never does. Re-run `scripts/replay_verdicts.py
  --local` (the reader's real summaries) and `grader_suite.py --local`
  after changing either model.
- **Isolated Claude calls.** `_claude.ask` runs the CLI with
  `--setting-sources "" --tools "" --strict-mcp-config` from `cwd=/`, images
  as base64 blocks. Long free text goes after `---TEXT---`, never inside JSON.
- **The ledger is the only value-carrying state**, HMAC-signed with the shared
  `/etc/workout-locker/hmac.key`. screen-locker and steam-backlog-enforcer
  read `credit` rows with `detail.bonus == "1"`, dated by `detail.ended_at`.
  The rule (`_bonus.py`), from `QUOTA_SWITCH_DATE` (2026-10-12): the day's
  credited pages reach the day's requirement (`Pace.ask.required`: quota
  after surplus moves + weekend debt share, ceil), stamped on the crossing
  row, one per day; a day asking 0 gets a zero-page `bonus:auto:<day>` row
  from the periodic runs (`_autogrant.py`: inbox pass, lock gate), once;
  before the switch 15 pages + 15 min, or 10 + 10 when on pace --
  judged at credit time. Consumers cannot judge pace, so a rule change
  reaches old rows only via `regrant` (zero-page `bonus:<id>` row).
  Changing that contract means changing both consumers in the same session.
- **Quotas** (`_quotas.py`, `_plan.py`): from the switch Tue-Thu 15, Mon/Fri
  30, Sat/Sun 50, weekends capped at 60 (debt included); surplus comes off
  Mon-Fri only, debt goes onto weekends only. The switch month keeps the old
  plan's line at the switch exactly -- never re-split the days before it.
- **Photos always first: indexing never runs in the photo pass.** A book
  file in `Reading/books/` is only marked `uploaded` by `process`, which
  starts `book-guard-index.service` (idle CPU/IO, resumable checkpoints)
  without waiting; `book-guard index` does the work under its own
  `index.lock`, never the ledger's `write.lock`. A page photo must never
  wait on an ebook being embedded.
- **Nothing credits without the grader** -- except a summary (150+ chars)
  that neither Claude nor the local model graded for `GRADER_GRACE` (5 min):
  `quiz_one` credits it with `detail.graded == "0"`. `detail.grader` names
  who judged a graded row (`claude:<model>` / `local:<model>`). The MCP server and the
  app's request files are read-only / route through `_grading.quiz_one`.
- **A fail names what is missing** (1-3 topics, never the answers); a
  failed summary can be rewritten any number of times (`<sid>#2`, `#3`, ...
  until a credit row), each judged generously and only on those topics
  (`_prompt.py`). The grader never fails on what it cannot verify against
  the text it was given (often just three photographed pages). Re-run
  `scripts/grader_suite.py` after touching it.
- **The PC never deletes the record**: the ledger, `Reading/processed/`,
  `Reading/thumbs/`, `Reading/sessions/`, `notes.json` and
  `summaries.json` (full summaries; the ledger row keeps `summary[:1000]`)
  only grow. A note edit keeps the replaced text under `previous`; an empty
  edit is refused, never a delete. Only the phone prunes (its 40 newest
  photos); the Library shows older ones from the PC's thumbs.
- **One writer at a time**: every read-modify-write of the ledger, the
  photo cache, `notes.json` or `summaries.json` happens inside
  `_flock.exclusive` -- never nested (a second `exclusive()` in the same
  process deadlocks; use the `*_unlocked` helper inside a held lock).
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
