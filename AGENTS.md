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
- `python -m scripts.pace_goldens` writes `app/test/fixtures/pace_goldens.json`,
  the answers the app's Dart port of the plan must match. Re-run it after
  touching `_quotas.py`, `_plan.py`, `_pace*.py` or `_ask.py`, and commit
  the fixture with the change (`test_pace_goldens_are_current` fails on a
  stale one).
- Heavy commands run under `~/.claude/scripts/capped.sh`; indexing a book
  needs `CAP_MEM=4G`.

## Invariants

- **No LLM reads page numbers, and the phone's number is trusted.** The
  phone (Tesseract4Android) reads it upright by content and the reader confirms or
  boxes it there; the PC takes that number as is -- no Tesseract re-read,
  no plausibility check, no "unclear". Tesseract is only the fallback for a
  photo that arrives with no number (desktop web upload, "Send anyway"):
  chosen by plausibility, ambiguous is a rejection that asks for a box,
  never a guess. A page photo must never wait on Claude.
  The one model allowed is the small local digit network for a *pencilled*
  number (`_pencil*.py`, weights `app/assets/pencil_digits.bin`, Dart port
  `app/lib/src/pencil_*.dart`, goldens `pencil_goldens.json`): no LLM, no
  network, never auto-accepted -- its answer only pre-fills the keypad the
  user confirms with one tap, and it runs only when the printed-number reader
  found nothing. Doubt is `None`, not a guess. After touching it re-run
  `scripts/page_truth.py` (rows with a `pencil` key; run a slice at a time:
  `... page_truth.py DIR 18:24`) and `python3 -m scripts.pencil_goldens`;
  retraining is `scripts/train_pencil.py` (chunks under 60 s).
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
  credited pages reach the day's requirement (`Pace.ask.bonus_at`: quota
  after surplus moves + weekend debt share, ceil; on a sick day the
  requirement it would have had, never 0 by sickness), stamped on the crossing
  row, one per day; a day asking 0 gets a zero-page `bonus:auto:<day>` row
  from the periodic runs (`_autogrant.py`: inbox pass, lock gate), once;
  before the switch 15 pages + 15 min, or 10 + 10 when on pace --
  judged at credit time. Consumers cannot judge pace, so a rule change
  reaches old rows only via `regrant` (zero-page `bonus:<id>` row).
  Changing that contract means changing both consumers in the same session.
- **Quotas** (`_quotas.py`, `_plan.py`): from the switch Tue-Thu 15, Mon/Fri
  30, Sat/Sun 50, weekends capped at 60. From `RESPLIT_DATE` (2026-10-18)
  **one number a day**: each morning re-splits what is left of the month by
  weight over the days left (`_resplit_mornings`); today's share is the
  requirement, the lock and the bonus alike. Days before it replay the old
  rules exactly (surplus off Mon-Fri, debt onto weekends, the 20-page pass)
  -- never re-split the days before a switch.
- **Both ends of a paper session count** (`_sessions.Session.pages` =
  stop - start + 1; a stop on the start page is 1 page, unless it comes under
  50 s after the start: then it is the start retaken). The check page is
  drawn from start..stop inclusive (`check_page_for`; the Dart
  `checkPageFor` must match -- literals pinned in `test_core_inclusive.py`
  and `local_session_test.dart`). In-app sessions keep end - start (their end
  is the first page not read). Rows written under this rule carry
  `detail.counting == "inclusive"` (`_quiz.record_verdict`); every older
  `session:<sha16>-<sha16>[#n]` credit gets exactly one signed +1 top-up,
  `inclusive:<id>` (same `day` and `detail.ended_at`, `detail.topup_of`, no
  bonus), from `book-guard backfill-inclusive [--dry-run]`
  (`_inclusive.py`, idempotent). Never top up a stamped row, never run
  `regrant` from it. The grading prompt was moved to match without a
  `grader_suite.py` re-run: re-run it.
- **The lock asks one question** (`_state._one_number`, `_pace.kept`): did
  yesterday keep its number? Missed -> locked until today's number is in.
  Kept = asked 0, read it, or carries the bonus. The timer only fires at the
  day boundary and the morning-carrot expiry; never add daytime hours.
- **Sick days never shrink the target** (`sickdays` pool, `_resplit.py`): a
  sick day asks 0 and never locks, and from `RESPLIT_DATE` it has no weight
  in the morning split, so its share moves to the days left; the month's
  target (1000) and the year balance stay whole, and what the old rules put
  in `MonthPlan.excused` (days before the resplit) is owed again from its
  morning. Never change the days before the resplit. The gate's verdict
  checks it first ("today is a sick day"). Every `compute_pace` caller
  passes `sick=` explicitly; the Dart port mirrors it (goldens). "Sick"
  here means `sickdays.stands_down(LOCKER_BOOK, day)`: a sick day that
  *keeps* `book` is a normal day, past or today (quota, debt, lock, bonus).
  `_sick.standing_down()` is the one read of the pool; never call
  `sickdays.sick_days()` elsewhere, or the gate and the bonus disagree.
- **An eased day** (`ease:<day>` row, `_actions.ease_day`, `_ease.py`):
  from `RESPLIT_DATE` its morning share is lowered by `amount` pages (floor
  0), read from the ledger inside `_pace._plan` so lock, bonus, `ask`, state
  JSON and the app all see one requirement. The pages are owed, not
  forgiven: the next morning re-splits what was not read, the month target
  and year balance stay whole (like sick days), the app gets
  `pace_inputs.eased` and its port mirrors it (goldens). It never rewrites a
  credit row; a bonus already stamped stays as it is (`regrant` is the
  user's call).
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
  `Reading/thumbs/`, `Reading/sessions/`, `notes.json`, `ebook_sessions.json`
  and `summaries.json` (full summaries; the ledger row keeps `summary[:1000]`)
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
- **In-app reading is credited in estimated paper pages** (`_ebook_map`,
  `_ebook`, `_ebook_sessions`): the PC's private map
  (`data_dir/ebook_maps/`) decides the pages, never the copy on the share
  or the app's numbers; the session clock is wall-clock from opening the
  reader (once its place has loaded) to leaving it -- a running start
  survives an app kill for 6 h; it never overlaps a countable paper
  session. The app's
  `ebook_map.dart` floors exactly like `_ebook_map.page_coordinate`
  (`app/test/fixtures/ebook_map_goldens.json`; regenerate with
  `BOOK_GUARD_WRITE_GOLDENS=1` on `test_core_ebook_map.py`). Served text
  offsets are Python code points = Dart UTF-16 units (astral -> U+FFFD).
  The photo grading prompt is pinned byte for byte (`test_core_prompt_pin`).

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
