import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/states.dart';

Future<void> _pump(
  WidgetTester tester, {
  GuardState? state,
  Object? error,
  Future<void> Function()? onRefresh,
}) => pumpTab(
  tester,
  StatusTab(state: state, error: error, onRefresh: onRefresh ?? () async {}),
);

void main() {
  testWidgets('waits for the PC before the first snapshot', (tester) async {
    await _pump(tester);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Waiting for the PC'), findsOneWidget);
  });

  testWidgets('shows a fetch error instead of the empty state', (tester) async {
    await _pump(tester, error: shareDown());
    expect(find.text('dufs Reading/x failed (500)'), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
  });

  testWidgets('a locked, behind month with todo and sessions', (tester) async {
    await _pump(
      tester,
      state: sampleState({
        'sessions': [
          ...fullState()['sessions'] as List,
          {'status': 'mystery', 'start_page': 5, 'end_page': 9},
        ],
      }),
    );
    expect(find.text('PC locked: Read 20 pages to unlock'), findsOneWidget);
    expect(find.text('2026-09'), findsOneWidget);
    expect(find.text('120 / 320 pages'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(120 / 320, 1e-9));
    expect(find.text("130 pages behind today's line (250)"), findsOneWidget);
    expect(
      find.text('Includes 20 pages carried from last month'),
      findsOneWidget,
    );
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Photograph page 42'), findsOneWidget);

    // The list builds lazily, so scroll each row into existence.
    Future<void> reveal(String text) =>
        tester.scrollUntilVisible(find.text(text), 100);
    await reveal('Sessions');
    // Newest first: the unknown status shows as-is, known ones in words.
    await reveal('mystery');
    expect(find.text('p. 5-9 (0 p, 0 min)'), findsOneWidget);
    await reveal('photograph the check page');
    expect(find.text('p. 1-20 (20 p, 30 min)'), findsOneWidget);
    expect(find.text('write the summary'), findsOneWidget);
    expect(find.text('credited'), findsOneWidget);
  });

  testWidgets('an unlocked month on pace, nothing to do', (tester) async {
    await _pump(
      tester,
      state: GuardState.fromJson(const {
        'reason': 'All good',
        'pace': {'month': '2026-10', 'required': 12},
      }),
    );
    expect(find.text('All good'), findsOneWidget);
    expect(find.text('0 / 0 pages'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
    expect(find.text('On pace (line today: 12)'), findsOneWidget);
    expect(find.textContaining('carried'), findsNothing);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Sessions'), findsNothing);
  });

  testWidgets('pace past the target is clamped to a full bar', (tester) async {
    await _pump(
      tester,
      state: GuardState.fromJson(const {
        'pace': {'target': 10, 'pages': 30},
      }),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
  });

  testWidgets('pull to refresh calls back', (tester) async {
    var refreshed = 0;
    await _pump(
      tester,
      state: sampleState(),
      onRefresh: () async => refreshed++,
    );
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await settle(tester, 20);
    expect(refreshed, 1);
    expect(sessionStatusText['too-fast'], contains('50 s'));
  });

  testWidgets('a session with details opens its history', (tester) async {
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
              'status': 'credited',
              'detail': 'sessions/s1.json',
            },
            {'id': 's2', 'start_page': 1, 'end_page': 3, 'status': 'credited'},
          ],
        }),
        error: null,
        onRefresh: () async {},
        api: api,
      ),
    );
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tapVisible(tester, find.text('p. 1-3 (0 p, 0 min)'));
    await tester.pumpAndSettle();
    expect(find.text('p. 1-3'), findsNothing);
    await tapVisible(tester, find.text('p. 7-51 (44 p, 43 min)'));
    await tester.pumpAndSettle();
    expect(find.text('p. 7-51'), findsOneWidget);
    expect(api.fetched, ['sessions/s1.json']);
  });

  testWidgets('without an api, sessions are not links', (tester) async {
    await _pump(
      tester,
      state: sampleState({
        'sessions': [
          {'id': 's1', 'detail': 'sessions/s1.json', 'status': 'credited'},
        ],
      }),
    );
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });
}
