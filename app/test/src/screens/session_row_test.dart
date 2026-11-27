import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/session_rows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';

SessionInfo _session(String status) => SessionInfo.fromJson({
  'id': 'session:a-b',
  'start_page': 10,
  'end_page': 29,
  'pages': 20,
  'minutes': 4,
  'status': status,
  'started_at': '2026-11-27T10:00:00+01:00',
  'ended_at': '2026-11-27T10:04:00+01:00',
});

void main() {
  testWidgets('a too-fast session shows its s/page beside the 35 floor', (
    tester,
  ) async {
    // kuhy, 2026-11-24: a fail must say why. 240 s / 20 pages = 12 s a page.
    await pumpTab(tester, SessionRow(session: _session('too-fast')));
    expect(find.text('12<35'), findsOneWidget);
    expect(find.byIcon(Icons.speed), findsOneWidget);
  });

  testWidgets('a counted session shows no speed', (tester) async {
    await pumpTab(tester, SessionRow(session: _session('credited')));
    expect(find.byIcon(Icons.speed), findsNothing);
  });
}
