import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/journal_fixtures.dart';

/// The PC's start of 2026-11-22: `book-guard start --page 260 --at 11:34`.
const _manualSha =
    '2914bcee1d4b4d6d8e226d2b79e99b84d6de39570a7b3a0fd7a55f54d84587cb';

void main() {
  GuardState pcStart() => GuardState.fromJson({
    'open_start': {
      'page': 260,
      'taken_at': journalStart.toIso8601String(),
      'sha': _manualSha,
      'manual': true,
    },
  });

  test('the PC open start is parsed with its hash and time', () {
    final state = pcStart();
    expect(state.openStart, 260);
    expect(state.openStartSha, _manualSha);
    expect(state.openStartAt, journalStart);
  });

  test('a stop pairs offline with a start the phone never took', () {
    final stop = journalEntry('stop_b.jpg', 'stop', 290, 40);
    final view = localView(pcStart(), [stop])!;
    expect(view.openStart, isNull);
    final session = view.needSummary.single;
    expect(session.status, 'needs-quiz');
    // book_guard._sessions.check_page_for on the same two hashes: 269.
    expect(session.checkPage, 269);
    expect(session.id, sessionId(_manualSha, stop.sha));
    expect((session.pages, session.minutes), (31, 40));
  });

  test('an old state without the hash still offers only the stop', () {
    final state = GuardState.fromJson({
      'open_start': {'page': 260},
    });
    expect(state.openStartSha, isNull);
    final view = localView(state, [journalEntry('s.jpg', 'stop', 290, 4)])!;
    expect(view.needSummary, isEmpty);
  });
}
