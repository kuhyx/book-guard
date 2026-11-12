/// The PC's reply codes as cues: one glyph and one tint per code, so a
/// reply is seen, not read. A code the app does not know, or a reply from an
/// older PC that carries only a sentence, gets the neutral error glyph.
library;

import 'package:book_guard_app/src/guard_response.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:material_ui/material_ui.dart';

const CueKind _ok = CueKind.ok;
const CueKind _info = CueKind.info;
const CueKind _warn = CueKind.warn;
const CueKind _error = CueKind.error;

/// Kind and glyph per reply code (see `book_guard/_requests.py` CODES).
const Map<String, (CueKind, IconData)> replyGlyphs = {
  'registered': (_ok, Icons.check_circle),
  'switched': (_ok, Icons.auto_stories),
  'found': (_ok, Icons.travel_explore),
  'saved': (_ok, Icons.check_circle),
  'requeued': (_ok, Icons.restore),
  'read': (_ok, Icons.check_circle),
  'times_set': (_ok, Icons.schedule),
  'note_saved': (_ok, Icons.check_circle),
  'note_updated': (_ok, Icons.check_circle),
  'note_kept': (_info, Icons.history),
  'recorded': (_ok, Icons.check_circle),
  'already_recorded': (_info, Icons.check_circle_outline),
  'passed': (_ok, Icons.check_circle),
  'ungraded': (_ok, Icons.check_circle_outline),
  'failed': (_error, Icons.cancel),
  'already_credited': (_info, Icons.verified),
  'queued': (_info, Icons.outbox),
  'not_yet': (_warn, Icons.hourglass_empty),
  'bad_isbn': (_error, Icons.qr_code_2),
  'bad_time': (_error, Icons.schedule),
  'outside_photos': (_error, Icons.schedule),
  'too_short': (_error, Icons.fast_forward),
  'bad_pages': (_error, Icons.last_page),
  'bad_note': (_error, Icons.edit_note),
  'bad_file': (_error, Icons.insert_drive_file),
  'offline': (_error, Icons.cloud_off),
  'unknown_isbn': (_warn, Icons.search_off),
  'unknown_book': (_error, Icons.search_off),
  'no_book': (_error, Icons.book_outlined),
  'not_waiting': (_warn, Icons.block),
  'no_session': (_warn, Icons.block),
  'already_graded': (_warn, Icons.lock_clock),
  'no_box': (_error, Icons.crop_free),
  'bad_page': (_error, Icons.pin),
  'no_page': (_error, Icons.crop_free),
  'no_photo': (_error, Icons.image_not_supported),
  'photo_gone': (_error, Icons.image_not_supported),
  'already_read': (_info, Icons.check_circle_outline),
  'overlap': (_error, Icons.filter_none),
  'paper_overlap': (_error, Icons.filter_none),
  'refused': (_error, Icons.block),
};

/// The neutral glyph for an unknown code or an old sentence-only reply.
const unknownReply = Cue(
  CueKind.info,
  icon: Icons.error_outline,
  semanticLabel: 'unknown reply',
);

/// The cue for [response].
Cue replyCue(GuardResponse response) {
  final code = response.code;
  final glyph = code == null ? null : replyGlyphs[code];
  if (glyph == null) return unknownReply;
  return Cue(
    glyph.$1,
    icon: glyph.$2,
    semanticLabel: code!.replaceAll('_', ' '),
  );
}

/// Shows [response] as an icon snackbar; a page number in its data (a
/// boxed photo read as page N) is shown beside the glyph.
void showReply(BuildContext context, GuardResponse response) {
  final page = response.number('page');
  showCue(
    context,
    replyCue(response),
    badge: page == null ? null : Text('$page'),
  );
}
