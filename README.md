# book-guard

Locks the PC while this month's **paper-book** reading is behind pace. Sixth
sibling of `screen-locker`, `leetcode-guard`, `diet-guard` and `wake-alarm`,
on the same [`gatelock`](https://github.com/kuhyx/utils/tree/main/gatelock)
lock window, HMAC key, free-day pool and sick-day pool.

## How reading is proven

Paper cannot be proven read, only made cheaper to read than to fake:

1. **Start** -- photograph the open page (page number visible).
2. **Stop** -- photograph the page where you stopped.
3. **Check** -- photograph the page book-guard then names: a random page
   between the two, derived from the photos' hashes, so it cannot be known
   in advance.
4. **Summary** -- 3-5 sentences in your own words, Polish or English.

**Page numbers never need Claude, the PC or a network.** The phone reads
each photo itself (ML Kit, bundled Latin model), turns it upright by its
*content* -- the camera's EXIF tag is wrong when it points straight down at
a book -- and shows the number it found boxed: tap another, or drag a box
around the right one; it is never typed. Everything (photo, its sidecar
note with the number's box, summaries, error entries) waits in an outbox
on the phone and goes to `~/data/cloud/Reading/` over dufs whenever the PC
answers; offline, the app names the check page and the session exactly as
the PC will. **The phone's number is the page**: the `.path` unit takes it
as is within seconds, and Tesseract only turns the photo upright and
transcribes it for the grader. A photo that arrives with no number (the
desktop web app, or "Send anyway") falls back to the PC: Tesseract reads
the boxed number or the whole page, zbar reads ISBN barcodes, and which
number is the page is decided by what the photo was for (check page asked
for, past the open start, nearest the last end) -- two candidates left is
"unclear", never a guess. Claude (**Haiku**, unless
`--model` is given for one run) only grades summaries and reads contents
pages; while it is down they wait, and the app says since when.
The EXIF capture times are
the session clock: under 50 s per page is page-flipping and does not count.

The grader reads the **book's own text** for the stretch when an ebook file
is attached (any format: epub, mobi, azw3, fb2, pdf, djvu, docx, ...). The
photographed pages are located in it with multilingual embeddings, so a
Polish paper copy anchors in an English epub, and Haiku gets the continuous
text between the start and end anchors -- not a handful of retrieved
snippets. Without a file, it grades on the three photos alone. Either way,
whatever it cannot check against the text it was given is never a reason
to fail -- only a clear contradiction, or a summary with no sign of the
reading (generic, a restatement of the photos, another book).

A passed session is a signed `credit` row in
`~/.local/share/book_guard/ledger.json`. A failed summary is told what it
is missing -- 1-3 topics from those pages, never the answers -- and may be
rewritten and resent **as often as it takes**, with the old text prefilled:
each rewrite is judged, generously, only on whether it now covers them
(`reject` rows `<session>`, `<session>#2`, `#3`, ... until a `credit` row
ends it). When Claude cannot grade (an outage, or usage running out), a
local model on ollama (`qwen3:32b`) grades instead, at once (`detail.grader
== "local:qwen3:32b"`); only if that is down too for 5 minutes is a summary
of 150+ characters credited without grading (`detail.graded == "0"`), bonus
included, so Claude never makes the app useless. A photographed contents
page falls back the same way, to `qwen3-vl:30b-a3b-instruct`.

## The rules

| | |
|---|---|
| Monthly target | 1000 pages plus this month's share of the year's balance, split over non-free days by weight: Tue-Thu 15, Mon/Fri 30, Sat/Sun 50 (from 2026-10-12; before it 20:40 Tue-Thu:Fri-Mon) |
| Weekend cap | a Sat/Sun never asks more than 60 pages, debt included; a month whose split would push weekends higher (February) pins them at 60 and spreads the rest over Mon-Fri, still 15:30 |
| Year balance | each month's 1000 minus pages read, summed: spread evenly over the months left in the year (this one included, odd pages first), a surplus lowering targets and a shortfall raising them, never below 0; December's balance lands whole on January |
| Today's number | **one number a day** (from 2026-10-18): each morning what is left of the month (target − pages read − sick days excused) is re-split by those weights over the days left, today included, weekends capped; today's share, rounded up, is today's number. Reading it is "on pace": it opens the lock and earns the bonus. It never moves during the day |
| Ahead / behind | a surplus or a shortfall is simply in the next morning's split: every later day asks a little less or a little more, by weight (a weekend too, up to 60); what no day can hold goes into the year balance |
| Lock | only on a day whose yesterday missed its number (a day asking 0 -- free, sick, read ahead -- or one carrying the bonus counts as kept; 2026-10-17 and before count as kept): from midnight or login until today's number is credited. Escapes and the morning-session carrot still apply |
| Before 2026-10-18 | the pace line `ceil(target * elapsed / counted)` (today's share due tomorrow), surplus off Mon-Fri, debt onto weekends, today's requirement = quota + weekend debt share, and a lock while behind the line at 10/14/18 h until caught up or 20 pages read. Those days' numbers are replayed as they were |
| Sick day | a date in the shared `sickdays` pool (not a free day) that does not keep `book` (`sickdays add --keep book` makes it a normal day here): the gate stands down all day and the day asks nothing. Its share is dropped, not re-split: the month's target falls by exactly that day's quota and every other day's quota is what it would have been. The share stays out of the year balance; pages read on it count as usual. An unreadable pool reads as no sick day (the gate applies) |
| Escape | 2 per month; forgives the day, credits no pages |
| Summary | a fail lists what to add; rewrite as often as needed, judged on that; Claude down: graded locally (ollama); ungraded credit after 5 min with no grader at all |
| Upload | within 7 days of the EXIF capture time (the phone queues offline) |
| Starts | 2026-10-01 |

**Bonuses** (read from the ledger by the consumers, fail closed): a day whose
credited pages (summed across sessions, dated by when the reading ended)
reach **today's requirement** earns **+1h** of shutdown time in
screen-locker and **+1h** of gaming in steam-backlog-enforcer, once per day;
the credit row that gets there carries the flag. A day that asks no pages
(a free day, or a weekday reading ahead already emptied) earns it without
reading: the next periodic run writes a zero-page `bonus:auto:<day>` row,
once. A sick day asks nothing but is no free hour: its bonus takes the
requirement the day would have had without being sick (`status --json`
`pace.today_required`; `pace.today_quota` is 0 and `sick_today` is true,
also in the MCP `get_status`). Before 2026-10-12 it was one
session of 15+ pages and 15+ minutes, or 10+ and 10+ when on pace. A day
that qualifies only later (a late-graded session lowered its requirement)
gets a zero-page bonus row from `book_guard regrant` (signed rows are never
edited; it is idempotent and `--dry-run` previews it). To pay for it, from 2026-10-01 the shutdown
base is 19:00 (cap 23:00) and the gaming base 4h (cap 8h).

## Use

```bash
book-guard search "Atomic Habits"      # find an ISBN by title
book-guard add 9780735211292 --file ~/Downloads/atomic.epub
book-guard pages 320                   # the last page of *your* copy
book-guard status                      # or: status --json
book-guard quiz                        # write the pending summary
book-guard ask --week                  # any day's requirement: --date D, --month,
                                       #   --simulate=-20@2026-10-16 (display only)
book-guard library                     # every book; --isbn X, --export md
book-guard index                       # index files dropped into Reading/books
```

A book file dropped into `Reading/books/` (or sent from the app's "Attach
book file") is never indexed by the photo pass: photos always come first.
The pass only marks it `uploaded` and starts `book-guard-index.service`, a
low-priority (idle CPU/IO) oneshot that runs `book-guard index`, also fired by
`book-guard-index.path` and a fallback `book-guard-index.timer`. Embedding
checkpoints, so a killed run resumes the book. Each stage
(`uploaded/extracting/embedding/done/failed`, with chunk progress) is
patched into `state.json` as `index_job`; a failed file moves to
`books/failed/` with its reason in `<file>.txt`, and the app's Retry queues
it again.

The Flutter app (`app/`) does all of it: Status (pace; tap a session for
its photos, what was read off them, your summary and the grader's reply),
Read (camera buttons that wait for the PC's verdict, summary, a gallery
of every photo), Book (Open Library + Biblioteka Narodowa search, a
typed ISBN, Edit with "Fill from ISBN", a contents photo that becomes
the chapter list, attach a book file with the indexing progress) and
Library (every book with its sessions, full summaries, grader replies and
your notes). Status also shows this week, the month grid, any picked day
and a ±N-page simulation, computed offline by a Dart port of the plan. Phone: installed APK with the `bookguard` dufs login. Desktop: `book-guard-desktop` serves
the web build on `localhost:8773` and opens it in a Chrome `--app` window;
it proxies WebDAV with the login, so the browser never holds it.

Failures from both sides land in `Reading/logs/errors.jsonl`, one JSON
object per line (the app's bug icon copies its own for pasting). A failed
photo can be boxed again or reported as "this should not fail": the report
(photo + both readings + the real page) is filed under
`~/.local/share/book_guard/reports/`, ready to become a row of
`scripts/page_truth.py`'s labelled photo set
(`~/data/book-guard_binaries/page_truth/`).

In a Claude session, `/book-check` relays a summary to the same grader
(Haiku-gated by a hook; `keep model` to override), and the read-only
`book-guard` MCP server offers `get_status`, `search_book`, `session_text`.

## Install

```bash
./install.sh                 # package, converters, systemd user units
scripts/setup_mcp.sh         # MCP venv + user-scope registration
~/src/dufs-cloud/scripts/add_dufs_login.sh bookguard /Reading rw
```
