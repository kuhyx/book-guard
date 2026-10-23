import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_state.dart';

/// An unreachable PC is a mode, not an error: say what still works.
Object explainOffline(Object error, GuardState? state, int waiting) {
  if (error is! DavException || error.status != 0) return error;
  final at = state?.generatedAt?.toLocal();
  final when = at == null
      ? ''
      : ' Showing the state from ${at.day}.${at.month} '
            '${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}.';
  final queued = waiting == 0
      ? ''
      : ' $waiting item(s) wait on the phone and go up automatically.';
  return 'Working offline - the PC cannot be reached.$when$queued '
      'Photos, page numbers and summaries all work offline.';
}
