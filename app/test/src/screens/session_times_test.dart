import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/session_times.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

SessionInfo _session({String status = 'needs-quiz'}) => SessionInfo.fromJson({
  'id': 'session:a-b',
  'start_page': 51,
  'end_page': 104,
  'pages': 53,
  'minutes': 121,
  'status': status,
  'started_at': '2026-10-03T12:27:38',
  'ended_at': '2026-10-03T14:29:00',
  'photo_start': '2026-10-03T12:27:38',
  'photo_end': '2026-10-03T14:29:00',
});

void main() {
  late FakeApi api;
  late int changed;

  setUp(() {
    api = FakeApi();
    changed = 0;
  });

  Future<void> pump(WidgetTester tester, SessionInfo session) => pumpTab(
    tester,
    SessionTimes(api: api, session: session, onChanged: () async => changed++),
  );

  testWidgets('shows when it was read; both pickers send the new times', (
    tester,
  ) async {
    api.onSend = (r) async =>
        const GuardResponse(ok: true, message: 'p. 51-104: 12:27-14:29');
    await pump(tester, _session());
    expect(find.text('Read 12:27-14:29 (121 min)'), findsOneWidget);
    await tester.tap(find.text('Correct the times'));
    await tester.pumpAndSettle();
    expect(find.text('When did you start reading?'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('When did you stop?'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final sent = api.sent.single;
    expect(sent.type, 'session_times');
    expect(sent.body['session_id'], 'session:a-b');
    expect('${sent.body['start']}', startsWith('2026-10-03T12:27'));
    expect('${sent.body['end']}', startsWith('2026-10-03T14:29'));
    expect(find.text('p. 51-104: 12:27-14:29'), findsOneWidget);
    expect(changed, 1);
  });

  testWidgets('a refusal is shown; cancelling sends nothing', (tester) async {
    api.onSend = (r) async => const GuardResponse(
      ok: false,
      message: '53 pages need at least 44 minutes.',
    );
    await pump(tester, _session());
    await tester.tap(find.text('Correct the times'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.sent, isEmpty);
    await tester.tap(find.text('Correct the times'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.sent, isEmpty);
    await tester.tap(find.text('Correct the times'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('53 pages need at least 44 minutes.'), findsOneWidget);
  });

  testWidgets('a graded session shows its times, no button', (tester) async {
    await pump(tester, _session(status: 'credited'));
    expect(find.text('Correct the times'), findsNothing);
  });

  testWidgets('no times known: nothing shown', (tester) async {
    await pump(tester, SessionInfo.fromJson(const {'id': 'x'}));
    expect(find.byType(Text), findsNothing);
  });

  test('a time before the day it is set on belongs to the next day', () {
    final day = DateTime(2026, 10, 3, 23, 30);
    expect(
      onDayOf(day, const TimeOfDay(hour: 0, minute: 20)),
      DateTime(2026, 10, 4, 0, 20),
    );
    expect(
      onDayOf(day, const TimeOfDay(hour: 23, minute: 45)),
      DateTime(2026, 10, 3, 23, 45),
    );
  });
}
