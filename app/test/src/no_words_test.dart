import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_api.dart';
import '../support/finders_a.dart';
import '../support/no_words.dart';
import '../support/no_words_home.dart';
import '../support/pace_inputs.dart';
import '../support/states.dart';

void main() {
  Future<void> home(WidgetTester tester, IconData tab) async {
    await pumpHome(tester, sampleState());
    await tester.tap(navTab(tab));
    await settle(tester);
  }

  for (final tab in [
    Icons.insights,
    Icons.menu_book,
    Icons.library_books,
    Icons.local_library,
  ]) {
    testWidgets('home tab $tab paints no words', (tester) async {
      await home(tester, tab);
      expectNoWords(tester, content: content);
    });
  }

  // --- Group A: status tab, pace panel, app shell ---

  GuardState paced(Map<String, dynamic> pace, {Map<String, dynamic>? inputs}) =>
      sampleState({
        'pace': {...fullState()['pace'] as Map<String, dynamic>, ...pace},
        'pace_inputs': ?inputs,
      });

  final states = <String, GuardState Function()>{
    'locked': sampleState,
    'unlocked': () => sampleState({'locked': false, 'reason': 'All good'}),
    'a sick day': () => paced(const {
      'daily': true,
      'today_required': 15,
      'today_quota': 0,
      'pages_today': 5,
    }),
    'a day met by the bonus': () => paced(const {
      'daily': true,
      'today_required': 30,
      'today_quota': 30,
      'pages_today': 5,
      'bonus_today': true,
    }),
    'excused sick days and carried debt': () =>
        paced(const {'excused': 45, 'carried_debt': 20}),
    'an eased day': () => paced(
      const {'daily': true, 'today_required': 12, 'today_quota': 12},
      inputs: {
        ...inputsJson(),
        'eased': {'2026-10-15': 5},
      },
    ),
    'every kind of todo line': () => sampleState({
      'todo': [
        'TAKE A PHOTO of page 42 (check for p. 1-20)',
        'REWRITE THE SUMMARY at the PC for p. 112-130',
        'WRITE A SUMMARY at the PC for p. 5-9',
        'Reading since p. 77 (Thu 10:00) -- photograph the page',
        "No book registered: search it in the app's Book tab",
      ],
    }),
    'every kind of session': () => sampleState({
      'sessions': [
        for (final (i, status) in [
          'needs-check-photo',
          'needs-quiz',
          'credited',
          'failed-quiz',
          'too-fast',
          'mystery',
        ].indexed)
          {
            'id': 's$i',
            'start_page': 1,
            'end_page': 5,
            'pages': 4,
            'minutes': 9,
            'status': status,
            'detail': 'sessions/s$i.json',
          },
        {
          'id': 'r',
          'status': 'needs-quiz',
          'retry': {'feedback': 'f', 'summary': 's', 'missing': <String>[]},
        },
      ],
    }),
  };
  for (final MapEntry(:key, :value) in states.entries) {
    testWidgets('the status tab paints no words: $key', (tester) async {
      await pumpHome(tester, value());
      expectNoWords(tester, content: content);
      await openPaceSheet(tester);
      expectNoWords(tester, content: content);
    });
  }

  testWidgets('the pace panel paints no words, also simulating', (
    tester,
  ) async {
    await pumpHome(
      tester,
      sampleState({
        'pace_inputs': inputsJson(credits: {'2026-10-13': 17}),
      }),
    );
    expectNoWords(tester, content: content);
    // The cells sit in the sheet behind the pace card.
    await openPaceSheet(tester);
    expectNoWords(tester, content: content);
    await tester.ensureVisible(iconLabeled('5 pages more'));
    await tester.tap(iconLabeled('5 pages more'));
    await settle(tester);
    expect(iconLabeled('reset'), findsOneWidget);
    expectNoWords(tester, content: content);
  });

  testWidgets('waiting, offline and error states paint no words', (
    tester,
  ) async {
    await pumpHome(tester, null);
    expect(iconLabeled('waiting for the PC'), findsOneWidget);
    expectNoWords(tester, content: content);
    await pumpHome(
      tester,
      sampleState(),
      setUp: (api) => api
        ..fetchError = const DavException('Reading/state.json', 0)
        ..offline = true,
    );
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expectNoWords(tester, content: content);
    await pumpHome(
      tester,
      null,
      setUp: (api) => api.fetchError = const DavException('x', 500),
    );
    expect(find.text('500'), findsOneWidget);
    expectNoWords(tester, content: content);
  });

  testWidgets('every kind of late answer paints no words', (tester) async {
    for (final response in const [
      GuardResponse(ok: true, code: 'passed', passed: true),
      GuardResponse(ok: false, code: 'failed', passed: false),
      GuardResponse(ok: true, code: 'queued'),
      GuardResponse(ok: false, code: 'not_yet'),
      GuardResponse(ok: true, code: 'read', data: {'page': 42}),
      GuardResponse(ok: false, code: 'no_such_code'),
      GuardResponse(ok: false),
    ]) {
      await pumpHome(
        tester,
        sampleState(),
        setUp: (api) => api.answers = [(what: 'summary', response: response)],
      );
      expect(shownCue, findsOneWidget);
      expectNoWords(tester, content: content);
    }
  });

  testWidgets('the wide desktop layout and the dark theme paint no words', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1600);
    addTearDown(tester.view.reset);
    final api = FakeApi(state: sampleState());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: HomeScreen(
          api: api,
          desktop: true,
          refreshEvery: const Duration(hours: 1),
        ),
      ),
    );
    await settle(tester);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    expectNoWords(tester, content: content);
    expect(iconLabeled('connection'), findsNothing);
  });
}
