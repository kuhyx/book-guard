import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_a.dart';
import '../../support/no_words.dart';
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
    expect(find.text('10 / 30'), findsOneWidget);
    expect(find.byIcon(Icons.today), findsOneWidget);
    expect(bar(tester), closeTo(10 / 30, 1e-9));
    expect(iconLabeled('pages still to read'), findsOneWidget);
    expect(find.text('20'), findsNWidgets(2)); // still to read, carried
    expect(find.text('10 · 2026'), findsOneWidget);
    expect(find.text('480 / 1000'), findsOneWidget);
    expect(iconLabeled('carried from last month'), findsOneWidget);
    expect(iconLabeled("today's line"), findsNothing);
    expect(iconLabeled('sick days excused'), findsNothing);
    expect(iconLabeled('met'), findsNothing);
    expectNoWords(tester);

    await _pump(tester, state: daily(today: 29, asks: 30));
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a daily day that met its number, or has the bonus', (
    tester,
  ) async {
    await _pump(tester, state: daily(today: 35, asks: 30));
    expect(find.text('35 / 30'), findsOneWidget);
    expect(bar(tester), 1);
    expect(iconLabeled('met'), findsOneWidget);
    expect(iconLabeled('pages still to read'), findsNothing);
    expect(iconLabeled('one hour earned'), findsOneWidget);

    await _pump(tester, state: daily(today: 5, asks: 30, bonus: true));
    expect(iconLabeled('met'), findsOneWidget);

    await _pump(tester, state: daily(today: 0, asks: 0));
    expect(bar(tester), 1);
    expect(iconLabeled('met'), findsOneWidget);
  });

  testWidgets('a sick day asks nothing but still earns the hour', (
    tester,
  ) async {
    await _pump(tester, state: daily(today: 5, asks: 15, quota: 0));
    expect(find.text('5 / 15'), findsOneWidget);
    expect(iconLabeled('sick day'), findsOneWidget);
    expect(find.text('10'), findsOneWidget); // still to read for the hour
    expect(iconLabeled('met'), findsNothing);

    await _pump(tester, state: daily(today: 14, asks: 15, quota: 0));
    expect(find.text('1'), findsOneWidget);

    await _pump(tester, state: daily(today: 15, asks: 15, quota: 0));
    expect(iconLabeled('sick day'), findsOneWidget);
    expect(iconLabeled('met'), findsOneWidget);
    expectNoWords(tester);
  });

  testWidgets('excused sick pages show in both cards', (tester) async {
    await _pump(tester, state: daily(today: 10, asks: 30, excused: 45));
    expect(iconLabeled('sick days excused'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    await _pump(
      tester,
      state: sampleState({
        'pace': {...fullState()['pace'] as Map<String, dynamic>, 'excused': 45},
      }),
    );
    expect(iconLabeled('sick days excused'), findsOneWidget);
    expect(find.text('130'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
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
    expect(find.text('09 · 2026'), findsOneWidget);
    expect(find.text('120 / 320'), findsOneWidget);
    expect(bar(tester), closeTo(120 / 320, 1e-9));
    expect(find.text('130'), findsOneWidget);
    expect(find.byIcon(Icons.today), findsNothing);
    expect(iconLabeled('sick days excused'), findsNothing);
  });
}
