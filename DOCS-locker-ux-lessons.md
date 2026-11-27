# Locker UX lessons (from book-guard, 2026-11-27)

kuhy, 2026-11-24, on book-guard: "the most annoying, rage-inducing locker
app of the big four (tutor, leetcode guard, workout app)". These are the
causes he named and what fixed each. Apply them to every new locker.

1. **Never make the user wait for the PC.** Every wait over 1 s was a
   complaint: OCR, grading, a desktop toast. The phone queues the photo or
   the summary and moves to the next step at once; the PC's answer comes
   back later as a cue (`send_capture.dart`, `sendQueued(wait: false)`).
   On the PC, slow work runs in its own unit and never blocks the fast pass
   (`book-guard-grade.service`, like `book-guard-index.service`). A
   subprocess the pass calls gets a short leash (`notify-send`: 0.9 s), so
   a dead daemon cannot stall it.
2. **Credit at the finish action.** The step the user takes last (the stop
   photo, the summary) closes the session. No extra proof step after it:
   the check page proved nothing a start and a stop do not, and it was one
   more wait.
3. **A fail always gives a reason, and only a real one.** All 7 real
   summary fails were false alarms ("only what the photos show", "too
   broad", "add details"). Fail only for what is clearly wrong (another
   book or another part, a contradiction), and show why: the 1-3 missing
   topics, or the measured speed beside its floor (`12<35` s/page).
4. **Fail open without a model.** No Claude usage left must cost nothing:
   a known outage goes straight to the local model, and a summary no model
   graded is credited after a grace counted from the submit.
5. **One distinct glyph and colour per step.** Start, stop and summary
   looked alike. Each has its own big glyph and colour (green play, red
   stop, amber pen); the camera is a small badge, and the tab badge and the
   status tile use the step's own glyph and colour.
