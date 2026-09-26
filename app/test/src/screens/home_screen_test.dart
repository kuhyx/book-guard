import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
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
    find.ancestor(
      of: find.byIcon(Icons.menu_book),
      matching: find.byType(Badge),
    ),
  );

  testWidgets('fetches on open and every refreshEvery', (tester) async {
    await pump(tester);
    expect(api.fetches, 1);
    expect(find.text('PC locked: Read 20 pages to unlock'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(api.fetches, 2);
    await tester.tap(find.byTooltip('Refresh'));
    await settle(tester);
    expect(api.fetches, 3);
  });

  testWidgets('the Read badge shows while a session waits', (tester) async {
    await pump(tester);
    expect(readBadge(tester).isLabelVisible, isTrue);
    api.state = sampleState({'sessions': const <Object>[]});
    await tester.tap(find.byTooltip('Refresh'));
    await settle(tester);
    expect(readBadge(tester).isLabelVisible, isFalse);
  });

  testWidgets('switches between the three tabs', (tester) async {
    await pump(tester, desktop: true);
    expect(find.byType(StatusTab), findsOneWidget);
    await tester.tap(find.text('Read'));
    await settle(tester);
    expect(find.byType(ReadTab), findsOneWidget);
    expect(tester.widget<ReadTab>(find.byType(ReadTab)).desktop, isTrue);
    await tester.tap(find.text('Book'));
    await settle(tester);
    expect(find.byType(BookTab), findsOneWidget);
    await tester.tap(find.text('Status'));
    await settle(tester);
    expect(find.byType(StatusTab), findsOneWidget);
  });

  testWidgets('a fetch error is shown and cleared by the next success', (
    tester,
  ) async {
    api.fetchError = shareDown();
    await pump(tester);
    expect(find.text('dufs Reading/x failed (500)'), findsOneWidget);
    api.fetchError = null;
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.text('dufs Reading/x failed (500)'), findsNothing);
    expect(find.text('PC locked: Read 20 pages to unlock'), findsOneWidget);
  });

  testWidgets('no settings button without a settings page', (tester) async {
    await pump(tester, desktop: true);
    expect(find.byTooltip('Connection'), findsNothing);
  });

  testWidgets('the settings button pushes the settings page', (tester) async {
    await pump(
      tester,
      settingsPage: () => const Scaffold(body: Text('settings page')),
    );
    await tester.tap(find.byTooltip('Connection'));
    await tester.pumpAndSettle();
    expect(find.text('settings page'), findsOneWidget);
  });

  testWidgets('a fetch finishing after close is dropped', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpWidget(const SizedBox());
    api.fetchError = shareDown();
    await settle(tester);
    expect(find.byType(HomeScreen), findsNothing);
  });
}
