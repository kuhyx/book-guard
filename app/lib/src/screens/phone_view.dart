import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/summary_store.dart';

/// What the phone itself knows, read with no network call: its photo
/// journal, the captures never sent, and the sessions whose summary is out
/// with the grader (they no longer hold up the next start).
typedef PhoneView = ({
  List<JournalEntry> journal,
  List<Capture> captures,
  Set<String> grading,
});

/// Reads the [PhoneView] over [state] (kuhy, 2026-11-24: never wait on the
/// PC -- a queued photo or a sent summary moves the Read tab on at once).
Future<PhoneView> phoneView(GuardApi api, GuardState? state) async {
  final journal = await api.journal.load();
  final captures = await api.captures.pending();
  final owed = localView(state, journal)?.needSummary ?? state?.needSummary;
  final grading = <String>{};
  for (final s in owed ?? const <SessionInfo>[]) {
    if (await api.gradingSince(s.id) != null) grading.add(s.id);
  }
  return (journal: journal, captures: captures, grading: grading);
}
