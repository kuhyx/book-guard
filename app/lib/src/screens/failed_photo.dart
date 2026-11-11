import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';

/// One photo taken here that did not come out as it should.
class FailedPhoto {
  /// Creates one.
  const new({required this.entry, required this.reason, this.pc});

  /// The phone's record of it.
  final JournalEntry entry;

  /// What went wrong, as the reader wrote it: data for a glyph and the
  /// report, never painted.
  final String reason;

  /// The PC's reading, once it has one.
  final PhotoInfo? pc;

  /// A pencilled number to pre-fill the keypad with (the phone's reading,
  /// else the PC's): a suggestion, never a page.
  int? get pencil => entry.pencilPage ?? pc?.pencilPage;
}

/// The photos taken here that failed: the PC rejected them, or the phone
/// could not read a page number and the PC has not read them yet.
List<FailedPhoto> failedPhotos(GuardState? state, List<JournalEntry> journal) {
  final byName = {
    for (final p in state?.photos ?? const <PhotoInfo>[]) p.name: p,
  };
  final known = knownToPc(state, journal);
  return [
    for (final e in journal.reversed)
      if (byName[e.name] case final pc? when !pc.accepted)
        FailedPhoto(entry: e, reason: pc.reason, pc: pc)
      else if (!known.contains(e.name) && e.page == null)
        FailedPhoto(entry: e, reason: phoneFoundNone),
  ];
}
