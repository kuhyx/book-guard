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

The app (phone camera, or the desktop window) uploads to
`~/data/cloud/Reading/` over dufs; the `.path` unit reads each photo within
seconds. Claude (**Haiku**, always, unless `--model` is given for one run)
reads the page number and transcribes the text. The EXIF capture times are
the session clock: under 50 s per page is page-flipping and does not count.

The grader reads the **book's own text** for the stretch when an ebook file
is attached (any format: epub, mobi, azw3, fb2, pdf, djvu, docx, ...). The
photographed pages are located in it with multilingual embeddings, so a
Polish paper copy anchors in an English epub, and Haiku gets the continuous
text between the start and end anchors -- not a handful of retrieved
snippets. Without a file, it grades on the photos and its own knowledge.

A passed session is a signed `credit` row in
`~/.local/share/book_guard/ledger.json`; a failed quiz is final.

## The rules

| | |
|---|---|
| Monthly target | 20 pages per Tue-Thu + 40 per Fri-Mon (220/week) over non-free days, plus debt carried from last month |
| Pace line | `ceil(target * elapsed / counted)`, days weighted by their quota; today's share is due tomorrow |
| Debt | 0 if a book was finished that month, else `target - pages read` |
| Lock | behind the line at login, 10:00, 14:00, 18:00 -- until caught up |
| Escape | 2 per month; forgives the day, credits no pages |
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

The Flutter app (`app/`) does all of it: Status, Read (camera buttons +
summary) and Book (title + optional author search, or a typed ISBN;
attach file). Phone: installed APK with the `bookguard` dufs login. Desktop: `book-guard-desktop` serves
the web build on `localhost:8773` and opens it in a Chrome `--app` window;
it proxies WebDAV with the login, so the browser never holds it.

In a Claude session, `/book-check` relays a summary to the same grader
(Haiku-gated by a hook; `keep model` to override), and the read-only
`book-guard` MCP server offers `get_status`, `search_book`, `session_text`.

## Install

```bash
./install.sh                 # package, converters, systemd user units
scripts/setup_mcp.sh         # MCP venv + user-scope registration
~/src/dufs-cloud/scripts/add_dufs_login.sh bookguard /Reading rw
```
