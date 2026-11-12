import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/session_times.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:material_ui/material_ui.dart';

/// While the PC's Claude is down: since when, and until when if it is
/// known -- both as numerals (`16:25`, or `15.10 16:25` on another day).
class GraderNote {
  /// Creates the note.
  const new({required this.since, this.until});

  /// When the outage began.
  final String since;

  /// When it ends, if known.
  final String? until;
}

/// Why a sent summary waits, while the PC's Claude is down -- null unless a
/// summary is [waiting] for its verdict and the outage still holds at [now].
///
/// The PC re-casts every vote on its local model whenever Claude fails, and
/// a local grade clears the outage -- so a note still showing may well mean
/// the local model failed too. If neither answers, the summary is credited
/// ungraded after 5 minutes.
GraderNote? graderNote(
  GuardState? state, {
  required bool waiting,
  required DateTime now,
}) {
  final since = state?.claudeDownSince;
  final until = state?.claudeDownUntil;
  if (!waiting || since == null) return null;
  if (until != null && !until.isAfter(now)) return null;
  return GraderNote(
    since: _when(since, now),
    until: until == null ? null : _when(until, now),
  );
}

/// `16:25` today, `15.10 16:25` on any other day.
String _when(DateTime moment, DateTime now) {
  final local = moment.toLocal();
  final days = _day(local).difference(_day(now.toLocal())).inDays;
  if (days == 0) return hhmm(local);
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')} ${hhmm(local)}';
}

/// Midnight UTC of [moment]'s calendar date: whole days apart, DST or not.
DateTime _day(DateTime moment) =>
    DateTime.utc(moment.year, moment.month, moment.day);

/// The note as a glyph: the grader is down (warn tint), `since` and `until`
/// as numerals; the PC tries its local model, nothing is lost.
class GraderNoteChip extends StatelessWidget {
  /// Creates the chip.
  const new(this.note, {super.key});

  /// What to show.
  final GraderNote note;

  @override
  Widget build(BuildContext context) {
    final until = note.until;
    return StatusCue(
      const Cue(
        CueKind.warn,
        icon: Icons.cloud_off,
        semanticLabel:
            'the grader is unavailable, the PC tries its local '
            'model',
      ),
      badge: Text(until == null ? note.since : '${note.since} - $until'),
    );
  }
}
