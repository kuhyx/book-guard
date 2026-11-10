import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/session_status_icon.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_a.dart';
import '../../support/no_words.dart';
import '../../support/states.dart';

Future<void> _pump(
  WidgetTester tester, {
  GuardState? state,
  Object? error,
  Future<void> Function()? onRefresh,
  int waiting = 0,
}) => pumpTab(
  tester,
  StatusTab(
    state: state,
    error: error,
    onRefresh: onRefresh ?? () async {},
    waiting: waiting,
  ),
);

void main() {
  testWidgets('waits for the PC before the first snapshot: an hourglass', (
    tester,
  ) async {
    await _pump(tester);
    expect(iconLabeled('waiting for the PC'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNothing);
    expectNoWords(tester);
  });

  testWidgets('a fetch error is the error glyph and its status number', (
    tester,
  ) async {
    await _pump(tester, error: shareDown());
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(iconLabeled('waiting for the PC'), findsNothing);
    expectNoWords(tester);
  });

  testWidgets('an unreachable PC is the cloud, the snapshot time, the queue', (
    tester,
  ) async {
    await _pump(
      tester,
      state: sampleState(),
      error: const DavException('Reading/state.json', 0),
      waiting: 3,
    );
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.textContaining('26.09'), findsOneWidget);
    expect(find.byIcon(Icons.outbox), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expectNoWords(tester);
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
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.byIcon(Icons.lock_open), findsNothing);
    expect(tester.widget<Icon>(find.byIcon(Icons.lock)).color, isNotNull);
    expect(find.text('09 · 2026'), findsOneWidget);
    expect(find.text('120 / 320'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(120 / 320, 1e-9));
    expect(find.byIcon(Icons.trending_down), findsOneWidget);
    expect(find.text('130'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(iconLabeled('carried from last month'), findsOneWidget);
    expect(find.text('20'), findsWidgets);

    // The todo line is its glyph and the number in it.
    expect(find.byIcon(Icons.photo_camera), findsWidgets);
    expect(find.text('42'), findsOneWidget);

    // The list builds lazily, so scroll each row into existence.
    Future<void> reveal(Finder finder) =>
        tester.scrollUntilVisible(finder, 100);
    // Newest first: the unknown status is a question mark.
    await reveal(find.byIcon(Icons.help_outline));
    expect(find.text('5-9'), findsOneWidget);
    await reveal(find.byIcon(Icons.edit));
    expect(find.text('21-0'), findsOneWidget);
    await reveal(iconLabeled('photograph the check page'));
    expect(find.text('1-20'), findsOneWidget);
    expect(find.text('30'), findsWidgets);
    expect(iconLabeled('credited'), findsOneWidget);
    expect(iconLabeled('write the summary'), findsOneWidget);
  });

  testWidgets('an unlocked month on pace, nothing to do', (tester) async {
    await _pump(
      tester,
      state: GuardState.fromJson(const {
        'reason': 'All good',
        'pace': {'month': '2026-10', 'required': 12},
      }),
    );
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNothing);
    expect(find.text('0 / 0'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
    expect(iconLabeled('on pace'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsNothing);
    expect(find.byIcon(Icons.arrow_right), findsNothing);
    expectNoWords(tester);
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
  });

  test('every session status has its own glyph, tint and spoken label', () {
    const known = [
      'needs-check-photo',
      'needs-quiz',
      'credited',
      'retry',
      'failed-quiz',
      'too-fast',
    ];
    expect({for (final s in known) iconFor(s)}, hasLength(known.length));
    expect(iconFor('odd'), Icons.help_outline);
    expect(spokenLabel('too-fast'), contains('50 s'));
    expect(spokenLabel('odd'), 'odd');
    expect(
      statusText(sampleState().sessions.first),
      spokenLabel('needs-check-photo'),
    );
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
    await tapVisible(tester, find.text('1-3'));
    await tester.pumpAndSettle();
    expect(api.fetched, isEmpty);
    await tapVisible(tester, find.text('7-51'));
    await tester.pumpAndSettle();
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

  testWidgets('a retry wins over the ledger status', (tester) async {
    await _pump(
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

  testWidgets('the PC lines become glyphs and page numbers, never words', (
    tester,
  ) async {
    await _pump(
      tester,
      state: sampleState({
        'todo': [
          'TAKE A PHOTO of page 42 (check for p. 1-20)',
          'REWRITE THE SUMMARY at the PC for p. 112-130',
          'WRITE A SUMMARY at the PC for p. 5-9',
          'Reading since p. 77 (Thu 10:00) -- photograph the page',
          "No book registered: search it in the app's Book tab",
        ],
        'sessions': const <Object>[],
      }),
    );
    for (final n in ['42', '1-20', '112-130', '5-9', '77', '10:00']) {
      expect(find.text(n), findsOneWidget, reason: n);
    }
    expect(find.byIcon(Icons.replay), findsOneWidget);
    expect(find.byIcon(Icons.auto_stories), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expectNoWords(tester);
  });
}
