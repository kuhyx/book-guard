/// The Book tab's status chips and snackbars: what an upload, a contents
/// reading or an indexing run is doing, as glyphs and numbers.
library;

import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:flutter/material.dart';

/// One upload step as a neutral chip: [icon] and, beside it, [badge].
Widget uploadStep(IconData icon, String spoken, {Widget? badge}) => StatusCue(
  Cue(CueKind.info, icon: icon, semanticLabel: spoken),
  badge: badge,
  key: ValueKey(spoken),
);

/// The chip for something kept on the phone until the PC is reachable.
Widget queuedChip() =>
    StatusCue(replyCue(const GuardResponse(ok: true, code: 'queued')));

/// The PC's reading of the contents photo as a chip: not read yet, not
/// accepted, or the number of chapters it found.
Widget contentsVerdict(PhotoInfo? read, int? chapters) {
  if (read == null) {
    return StatusCue(replyCue(const GuardResponse(ok: false, code: 'not_yet')));
  }
  if (!read.accepted) {
    return const StatusCue(
      Cue(
        CueKind.error,
        icon: Icons.image_not_supported,
        semanticLabel: 'Not accepted: retake it',
      ),
    );
  }
  return StatusCue(
    const Cue(
      CueKind.ok,
      icon: Icons.format_list_numbered,
      semanticLabel: 'Contents read',
    ),
    badge: chapters == null ? null : Text('$chapters'),
  );
}

/// A picked file the PC cannot read: the error glyph and the file's name.
void showUnreadableFormat(BuildContext context, String name) => showCue(
  context,
  const Cue(
    CueKind.error,
    icon: Icons.insert_drive_file,
    semanticLabel: 'The PC cannot read this format',
  ),
  badge: Text(name),
);

/// How following an uploaded book's indexing ended: [job] is the finished
/// job, or null when the PC is still at it (the card keeps showing it).
void showFollowEnd(BuildContext context, IndexJob? job) {
  if (job == null) {
    showCue(
      context,
      const Cue(
        CueKind.warn,
        icon: Icons.hourglass_top,
        semanticLabel: 'Still indexing',
      ),
    );
  } else if (job.stage == 'done') {
    showCue(
      context,
      const Cue(
        CueKind.ok,
        icon: Icons.file_present,
        semanticLabel: 'Book file attached',
      ),
    );
  }
}

/// Writes a failed (or stalled) [job]'s reason to the error log, once per
/// failure; [logged] is the key of the last one written. Returns the key to
/// pass next time. The reason is for the log, never the screen.
String logIndexFailure(GuardApi api, IndexJob? job, String logged) {
  if (job == null || !job.hasFailed(DateTime.now())) return logged;
  final key = '${job.file}|${job.updatedAt}';
  if (key == logged) return logged;
  unawaited(
    api.errors.log('index', job.error.isEmpty ? job.stage : job.error, {
      'file': job.file,
    }),
  );
  return key;
}
