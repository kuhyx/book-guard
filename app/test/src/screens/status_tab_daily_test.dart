import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/states.dart';

// The one-number card (from the PC's resplit): today first, then the month.

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
  /// A one-number day: [today] read of [asks]; [quota] 0 on a sick day.
  GuardState daily({
    required int today,
    required int asks,
    int? quota,
    bool bonus = false,
    int excused = 0,
    int carried = 0,
  }) => GuardState.fromJson({
    'pace': {
      'month': '2026-10',
      'target': 1000,
      'pages': 480,
      'required': 500,
      'behind': 20,
      'carried_debt': carried,
      'daily': true,
      'excused': excused,
      'today_required': asks,
      'today_quota': quota ?? asks,
      'pages_today': today,
      'bonus_today': bonus,
    },
  });

  double bar(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
      .value!;

  testWidgets('a daily day short of its number: today first', (tester) async {
    await _pump(tester, state: daily(today: 10, asks: 30, carried: 20));
    expect(find.text('Today: 10 / 30 pages'), findsOneWidget);
    expect(bar(tester), closeTo(10 / 30, 1e-9));
    expect(
      find.text('20 more pages today: on pace, PC open, +1h'),
      findsOneWidget,
    );
    expect(find.text('2026-10: 480 / 1000 pages'), findsOneWidget);
    expect(
      find.text('Includes 20 pages carried from last month'),
      findsOneWidget,
    );
    expect(find.textContaining('line'), findsNothing);
    expect(find.textContaining('excused'), findsNothing);

    await _pump(tester, state: daily(today: 29, asks: 30));
    expect(
      find.text('1 more page today: on pace, PC open, +1h'),
      findsOneWidget,
    );
  });

  testWidgets('a daily day that met its number, or has the bonus', (
    tester,
  ) async {
    await _pump(tester, state: daily(today: 35, asks: 30));
    expect(find.text('Today: 35 / 30 pages'), findsOneWidget);
    expect(bar(tester), 1);
    expect(find.text('On pace: PC open, +1h earned'), findsOneWidget);

    await _pump(tester, state: daily(today: 5, asks: 30, bonus: true));
    expect(find.text('On pace: PC open, +1h earned'), findsOneWidget);

    await _pump(tester, state: daily(today: 0, asks: 0));
    expect(bar(tester), 1);
    expect(find.text('On pace: PC open, +1h earned'), findsOneWidget);
  });

  testWidgets('a sick day asks nothing but still earns the hour', (
    tester,
  ) async {
    await _pump(tester, state: daily(today: 5, asks: 15, quota: 0));
    expect(find.text('Today: 5 / 15 pages'), findsOneWidget);
    expect(
      find.text('Sick day: nothing asked; 10 more pages still earn the +1h'),
      findsOneWidget,
    );
    expect(find.textContaining('PC open'), findsNothing);

    await _pump(tester, state: daily(today: 14, asks: 15, quota: 0));
    expect(
      find.text('Sick day: nothing asked; 1 more page still earns the +1h'),
      findsOneWidget,
    );

    await _pump(tester, state: daily(today: 15, asks: 15, quota: 0));
    expect(find.text('Sick day: +1h earned'), findsOneWidget);
  });

  testWidgets('excused sick pages show in both cards', (tester) async {
    const line = 'Sick days excused: 45 pages off the target';
    await _pump(tester, state: daily(today: 10, asks: 30, excused: 45));
    expect(find.text(line), findsOneWidget);
    await _pump(
      tester,
      state: sampleState({
        'pace': {...fullState()['pace'] as Map<String, dynamic>, 'excused': 45},
      }),
    );
    expect(find.text(line), findsOneWidget);
    expect(find.text("130 pages behind today's line (250)"), findsOneWidget);
  });

  testWidgets('an older PC (not daily) keeps the month card', (tester) async {
    await _pump(
      tester,
      state: sampleState({
        'pace': {
          ...fullState()['pace'] as Map<String, dynamic>,
          'today_required': 30,
          'pages_today': 10,
        },
      }),
    );
    expect(find.text('2026-09'), findsOneWidget);
    expect(find.text('120 / 320 pages'), findsOneWidget);
    expect(bar(tester), closeTo(120 / 320, 1e-9));
    expect(find.text("130 pages behind today's line (250)"), findsOneWidget);
    expect(find.textContaining('Today:'), findsNothing);
    expect(find.textContaining('excused'), findsNothing);
  });
}
