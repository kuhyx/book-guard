import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/finders_a.dart';
import '../../support/states.dart';
import '../../support/status_pump.dart';

// Status tab: the session tiles, the all-sessions sheet and their links.
void main() {
  testWidgets('done sessions get no tile; the history sheet lists all', (
    tester,
  ) async {
    await pumpStatus(
      tester,
      state: sampleState({
        'todo': const <Object>[],
        'sessions': [
          for (var i = 1; i <= 3; i++)
            {'id': 's$i', 'start_page': i, 'end_page': i, 'status': 'credited'},
          {'id': 'f', 'start_page': 4, 'end_page': 4, 'status': 'failed-quiz'},
          {'id': 't', 'start_page': 5, 'end_page': 5, 'status': 'too-fast'},
          {'id': 'o', 'start_page': 6, 'end_page': 6, 'status': 'needs-quiz'},
        ],
      }),
    );
    // Only the open one on the main screen.
    expect(find.text('6-6'), findsOneWidget);
    for (final done in ['1-1', '2-2', '3-3', '4-4', '5-5']) {
      expect(find.text(done), findsNothing);
    }
    await tester.tap(iconLabeled('all sessions'));
    await tester.pumpAndSettle();
    expect(find.text('1-1'), findsOneWidget);
    expect(find.text('5-5'), findsOneWidget);
  });

  testWidgets('past six open sessions the rest wait behind a sheet', (
    tester,
  ) async {
    await pumpStatus(
      tester,
      state: sampleState({
        'todo': const <Object>[],
        'sessions': [
          for (var i = 1; i <= 8; i++)
            {
              'id': 's$i',
              'start_page': i,
              'end_page': i,
              'status': 'needs-check-photo',
            },
        ],
      }),
    );
    expect(find.text('8-8'), findsOneWidget);
    expect(find.text('3-3'), findsOneWidget);
    expect(find.text('2-2'), findsNothing);
    await tester.tap(iconLabeled('all sessions'));
    await tester.pumpAndSettle();
    expect(find.text('2-2'), findsOneWidget);
  });

  testWidgets('nothing open, nothing done: no session tiles at all', (
    tester,
  ) async {
    await pumpStatus(
      tester,
      state: sampleState({
        'todo': const <Object>[],
        'sessions': const <Object>[],
      }),
    );
    expect(iconLabeled('all sessions'), findsNothing);
  });

  testWidgets('without pace inputs the pace card opens nothing', (
    tester,
  ) async {
    await pumpStatus(tester, state: sampleState());
    expect(iconLabeled('pace details'), findsNothing);
  });

  testWidgets('a session with details opens its history', (tester) async {
    tallPhone(tester);
    final api = FakeApi();
    await pumpTab(
      tester,
      StatusTab(
        state: sampleState({
          'sessions': [
            {
              'id': 's1',
              'start_page': 7,
              'end_page': 51,
              'pages': 44,
              'minutes': 43,
              'status': 'needs-quiz',
              'detail': 'sessions/s1.json',
            },
            {
              'id': 's2',
              'start_page': 1,
              'end_page': 3,
              'status': 'needs-quiz',
            },
          ],
        }),
        error: null,
        api: api,
      ),
    );
    await tapVisible(tester, find.text('1-3'));
    await tester.pumpAndSettle();
    expect(api.fetched, isEmpty);
    await tapVisible(tester, find.text('7-51'));
    await tester.pumpAndSettle();
    expect(api.fetched, ['sessions/s1.json']);
  });

  testWidgets('without an api, sessions are not links', (tester) async {
    await pumpStatus(
      tester,
      state: sampleState({
        'sessions': [
          {'id': 's1', 'detail': 'sessions/s1.json', 'status': 'needs-quiz'},
        ],
      }),
    );
    await tester.tap(find.byIcon(Icons.edit).last);
    await tester.pumpAndSettle();
    expect(find.byType(StatusTab), findsOneWidget);
  });

  testWidgets('a retry wins over the ledger status', (tester) async {
    await pumpStatus(
      tester,
      state: sampleState({
        'sessions': [
          {
            'id': 's1',
            'start_page': 1,
            'end_page': 9,
            'status': 'needs-quiz',
            'retry': {'feedback': 'f', 'summary': 's', 'missing': <String>[]},
          },
        ],
      }),
    );
    expect(find.byIcon(Icons.replay), findsOneWidget);
    expect(iconLabeled('summary failed: rewrite it'), findsOneWidget);
  });
}
