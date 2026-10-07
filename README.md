# book-guard

Locks the PC while this month's **paper-book** reading is behind pace. Sixth
sibling of `screen-locker`, `leetcode-guard`, `diet-guard` and `wake-alarm`,
on the same [`gatelock`](https://github.com/kuhyx/utils/tree/main/gatelock)
lock window, HMAC key and free-day pool.

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
ends it). If the grader cannot be reached for an hour
(an outage, or Claude usage running out), a summary of 150+ characters is
credited without grading (`detail.graded == "0"`), bonus included, so Claude
never makes the app useless.

## The rules

| | |
|---|---|
| Monthly target | 20 pages per Tue-Thu + 40 per Fri-Mon (220/week) over non-free days, plus debt carried from last month |
| Pace line | `ceil(target * elapsed / counted)`, days weighted by their quota; today's share is due tomorrow |
| Debt | 0 if a book was finished that month, else `target - pages read` |
| Lock | behind the line at login, 10:00, 14:00, 18:00 -- until caught up |
| Escape | 2 per month; forgives the day, credits no pages |
| Summary | a fail lists what to add; rewrite as often as needed, judged on that; ungraded credit after 1 h of grader outage |
| Upload | within 7 days of the EXIF capture time (the phone queues offline) |
| Starts | 2026-10-01 |

**Bonuses** (read from the ledger by the consumers, fail closed): a credited
session of 20+ pages and 20+ minutes earns **+1h** of shutdown time in
screen-locker and **+1h** of gaming in steam-backlog-enforcer, once per day,
dated by when the reading ended. To pay for it, from 2026-10-01 the shutdown
base is 19:00 (cap 23:00) and the gaming base 4h (cap 8h).

## Use

```bash
book-guard search "Atomic Habits"      # find an ISBN by title
book-guard add 9780735211292 --file ~/Downloads/atomic.epub
book-guard pages 320                   # the last page of *your* copy
book-guard status                      # or: status --json
book-guard quiz                        # write the pending summary
```

The Flutter app (`app/`) does all of it: Status (pace; tap a session for
its photos, what was read off them, your summary and the grader's reply),
Read (camera buttons that wait for the PC's verdict, summary, a gallery
of every photo) and Book (Open Library + Biblioteka Narodowa search, a
typed ISBN, Edit with "Fill from ISBN", a contents photo that becomes
the chapter list, attach file). Phone: installed APK with the `bookguard` dufs login. Desktop: `book-guard-desktop` serves
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
