import 'dart:convert';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_a.dart';
import '../../support/no_words.dart';
import '../../support/states.dart';

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi(state: sampleState()));

  Future<void> pump(
    WidgetTester tester, {
    bool desktop = false,
    Widget Function()? settingsPage,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: HomeScreen(
          api: api,
          desktop: desktop,
          settingsPage: settingsPage,
          refreshEvery: const Duration(seconds: 1),
        ),
      ),
    );
    await settle(tester);
    // Dispose at the end so the periodic refresh timer is cancelled.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Badge readBadge(WidgetTester tester) => tester.widget<Badge>(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byType(Badge),
    ),
  );

  testWidgets('fetches on open and every refreshEvery', (tester) async {
    await pump(tester);
    expect(api.fetches, 1);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(api.fetches, 2);
    await tester.tap(iconLabeled('refresh'));
    await settle(tester);
    expect(api.fetches, 3);
  });

  testWidgets('the Read badge shows while a session waits', (tester) async {
    await pump(tester);
    expect(readBadge(tester).isLabelVisible, isTrue);
    api.state = sampleState({'sessions': const <Object>[]});
    await tester.tap(iconLabeled('refresh'));
    await settle(tester);
    expect(find.byType(Badge), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(Badge),
      ),
      findsNothing,
    );
  });

  testWidgets('switches between the three tabs', (tester) async {
    await pump(tester, desktop: true);
    expect(find.byType(StatusTab), findsOneWidget);
    await tester.tap(navTab(Icons.menu_book));
    await settle(tester);
    expect(find.byType(ReadTab), findsOneWidget);
    expect(tester.widget<ReadTab>(find.byType(ReadTab)).desktop, isTrue);
    await tester.tap(navTab(Icons.library_books));
    await settle(tester);
    expect(find.byType(BookTab), findsOneWidget);
    await tester.tap(navTab(Icons.insights));
    await settle(tester);
    expect(find.byType(StatusTab), findsOneWidget);
  });

  testWidgets('a fetch error is shown and cleared by the next success', (
    tester,
  ) async {
    api.fetchError = shareDown();
    await pump(tester);
    expect(find.text('500'), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
    api.fetchError = null;
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.byIcon(Icons.error), findsNothing);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('no settings button without a settings page', (tester) async {
    await pump(tester, desktop: true);
    expect(iconLabeled('connection'), findsNothing);
  });

  testWidgets('the settings button pushes the settings page', (tester) async {
    await pump(
      tester,
      settingsPage: () => const Scaffold(body: Text('settings page')),
    );
    await tester.tap(iconLabeled('connection'));
    await tester.pumpAndSettle();
    expect(find.text('settings page'), findsOneWidget);
  });

  testWidgets('the bar paints no title and no tooltip', (tester) async {
    await pump(tester);
    expectNoWords(tester);
  });

  testWidgets('a fetch finishing after close is dropped', (tester) async {
    await pump(tester);
    await tester.tap(iconLabeled('refresh'));
    await tester.pumpWidget(const SizedBox());
    api.fetchError = shareDown();
    await settle(tester);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('an unreachable PC is offline mode, on the last snapshot', (
    tester,
  ) async {
    await api.store.write(
      'state.json',
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'reason': 'on pace',
            'generated_at': '2026-10-03T10:58:04Z',
          }),
        ),
      ),
    );
    api
      ..fetchError = const DavException('Reading/state.json', 0, 'unreachable')
      ..offline = true;
    await pump(tester);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.textContaining('03.10'), findsOneWidget);
    expect(find.byIcon(Icons.outbox), findsOneWidget);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
  });

  testWidgets('offline with nothing cached or queued is just the cloud', (
    tester,
  ) async {
    api.fetchError = const DavException('Reading/state.json', 0);
    await pump(tester);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.byIcon(Icons.outbox), findsNothing);
    expect(find.byIcon(Icons.history), findsNothing);
  });

  testWidgets('late answers are one cue, the worst kind, with a count', (
    tester,
  ) async {
    api.answers = [
      (
        what: 'summary',
        response: const GuardResponse(ok: true, code: 'passed', passed: true),
      ),
      (
        what: 'reread',
        response: const GuardResponse(ok: false, code: 'no_page'),
      ),
    ];
    await pump(tester);
    expect(shownCue, findsOneWidget);
    expect(shownCueKind(tester), CueKind.error);
    expect(inShownCue(Icons.crop_free), findsOneWidget);
    expect(
      find.descendant(of: shownCue, matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('a good late answer is an ok cue', (tester) async {
    api.answers = [
      (
        what: 'summary',
        response: const GuardResponse(ok: true, code: 'passed', passed: true),
      ),
    ];
    await pump(tester);
    expect(shownCueKind(tester), CueKind.ok);
    expect(inShownCue(Icons.check_circle), findsOneWidget);
  });

  testWidgets('an unknown failed reply is an error, never a sentence', (
    tester,
  ) async {
    api.answers = [(what: 'note', response: const GuardResponse(ok: false))];
    await pump(tester);
    expect(shownCueKind(tester), CueKind.error);
    expectNoWords(tester);
  });

  testWidgets('diagnostics go to the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    await api.errors.log('photo', 'no page number found');
    await pump(tester);
    await tester.tap(iconLabeled('copy diagnostics'));
    await settle(tester);
    expect(copied, contains('no page number found'));
    expect(shownCueKind(tester), CueKind.ok);
    expect(inShownCue(Icons.check_circle), findsNothing);
    expect(inShownCue(Icons.content_paste), findsOneWidget);
  });
}
