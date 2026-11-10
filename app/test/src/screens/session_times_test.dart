import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/icon_time_dialog.dart';
import 'package:book_guard_app/src/screens/picker_parts.dart';
import 'package:book_guard_app/src/screens/session_times.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_book.dart';
import '../../support/no_letters.dart';

/// Turns wheel [index] (start h, start m, end h, end m) by [notches].
Future<void> scrollWheel(WidgetTester tester, int index, int notches) async {
  final at = tester.getCenter(find.byType(NumberWheel).at(index));
  final mouse = TestPointer(1, PointerDeviceKind.mouse)..hover(at);
  for (var i = 0; i < notches.abs(); i++) {
    await tester.sendEventToBinding(mouse.scroll(Offset(0, notches * 40.0)));
  }
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.check));
  await tester.pumpAndSettle();
}

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
    api.onSend = (r) async => const GuardResponse(ok: true, code: 'times_set');
    await pump(tester, _session());
    expect(find.text('12:27-14:29'), findsOneWidget);
    expect(find.text('121'), findsOneWidget);
    await tester.tap(iconLabeled('Correct the times'));
    await tester.pumpAndSettle();
    expect(find.byType(IconTimeRangeDialog), findsOneWidget);
    expect(find.byType(NumberWheel), findsNWidgets(4));
    await confirm(tester);
    final sent = api.sent.single;
    expect(sent.type, 'session_times');
    expect(sent.body['session_id'], 'session:a-b');
    expect('${sent.body['start']}', startsWith('2026-10-03T12:27'));
    expect('${sent.body['end']}', startsWith('2026-10-03T14:29'));
    expect(cueGlyph(Icons.schedule), findsOneWidget);
    expect(cueOf(CueKind.ok), findsOneWidget);
    expect(changed, 1);
  });

  testWidgets('a refusal is shown; cancelling sends nothing', (tester) async {
    api.onSend = (r) async => const GuardResponse(
      ok: false,
      code: 'too_short',
      data: {'pages': 53, 'minutes': 44},
    );
    await pump(tester, _session());
    await tester.tap(iconLabeled('Correct the times'));
    await tester.pumpAndSettle();
    await scrollWheel(tester, 0, 1);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(api.sent, isEmpty);
    await tester.tap(iconLabeled('Correct the times'));
    await tester.pumpAndSettle();
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    expect(api.sent, isEmpty, reason: 'a dismiss sends nothing');
    await tester.tap(iconLabeled('Correct the times'));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(cueGlyph(Icons.fast_forward), findsOneWidget);
    expect(cueOf(CueKind.error), findsOneWidget);
    expect(
      glyphNumber(cueGlyph(Icons.fast_forward), '53 / 44'),
      findsOneWidget,
    );
  });

  testWidgets('an end before the start shows +1 and ends the next day', (
    tester,
  ) async {
    api.onSend = (r) async => const GuardResponse(ok: true, code: 'times_set');
    await pump(tester, _session());
    await tester.tap(iconLabeled('Correct the times'));
    await tester.pumpAndSettle();
    expect(find.text('+1'), findsNothing);
    await scrollWheel(tester, 2, -3); // end 14:29 -> 11:29, start 12:27
    expect(find.text('+1'), findsOneWidget);
    await scrollWheel(tester, 1, 1); // the start minute moves, not the hour
    await confirm(tester);
    final sent = api.sent.single;
    expect('${sent.body['start']}', startsWith('2026-10-03T12:28'));
    expect('${sent.body['end']}', startsWith('2026-10-04T11:29'));
  });

  testWidgets('the times picker paints no words', (tester) async {
    await pump(tester, _session());
    await tester.tap(iconLabeled('Correct the times'));
    await tester.pumpAndSettle();
    await scrollWheel(tester, 2, -3);
    expectNoLetters(
      tester,
      find.byType(IconTimeRangeDialog),
      spoken: [Icons.check, Icons.close, Icons.play_arrow, Icons.stop],
    );
  });

  testWidgets('a graded session shows its times, no button', (tester) async {
    await pump(tester, _session(status: 'credited'));
    expect(iconLabeled('Correct the times'), findsNothing);
    expect(find.text('12:27-14:29'), findsOneWidget);
  });

  testWidgets('no times known: nothing shown', (tester) async {
    await pump(tester, SessionInfo.fromJson(const {'id': 'x'}));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a time outside the photos shows the photos span', (
    tester,
  ) async {
    api.onSend = (r) async => const GuardResponse(
      ok: false,
      code: 'outside_photos',
      data: {'first': '12:27', 'last': '14:29'},
    );
    await pump(tester, _session());
    await tester.tap(iconLabeled('Correct the times'));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(glyphNumber(cueOf(CueKind.error), '12:27-14:29'), findsOneWidget);
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
