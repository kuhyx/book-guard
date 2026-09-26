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
- `scripts/grader_suite.py [MODEL]` is the adversarial check of the vision
  reader and grader on a real model (needs the sandbox demo session). Re-run
  it after touching `_quiz.py`, `_vision.py`, `_anchor.py` or the prompts.
- Heavy commands run under `~/.claude/scripts/capped.sh`; indexing a book
  needs `CAP_MEM=4G`.

## Invariants

- **Haiku only.** Every Claude call defaults to `DEFAULT_MODEL = "haiku"`;
  another model only via an explicit per-run `--model`. Never a config value.
- **Isolated Claude calls.** `_claude.ask` runs the CLI with
  `--setting-sources "" --tools "" --strict-mcp-config` from `cwd=/`, images
  as base64 blocks. Long free text goes after `---TEXT---`, never inside JSON.
- **The ledger is the only value-carrying state**, HMAC-signed with the shared
  `/etc/workout-locker/hmac.key`. screen-locker and steam-backlog-enforcer
  read `credit` rows with `detail.bonus == "1"`, dated by `detail.ended_at`.
  Changing that contract means changing both consumers in the same session.
- **Nothing credits without the grader.** The MCP server and the app's
  request files are read-only / route through `_grading.quiz_one`.
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
