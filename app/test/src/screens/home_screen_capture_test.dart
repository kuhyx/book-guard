import 'dart:convert';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/states.dart';

/// The home screen's part in keeping photos: a camera cut off by a
/// restart, and leaving / returning to the app, both logged.
void main() {
  late FakeApi api;

  setUp(() => api = FakeApi(state: sampleState()));

  Future<void> pump(WidgetTester tester, {LostPhoto? lostPhoto}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: HomeScreen(
          api: api,
          desktop: false,
          refreshEvery: const Duration(seconds: 1),
          lostPhoto: lostPhoto,
        ),
      ),
    );
    await settle(tester);
    // Dispose at the end so the periodic refresh timer is cancelled.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('a photo the camera kept across a restart is offered', (
    tester,
  ) async {
    await api.captures.launching('a1', 'start');
    await pump(
      tester,
      lostPhoto: () async => ('IMG.jpg', Uint8List.fromList([1])),
    );
    await tester.tap(find.text('Read'));
    await settle(tester);
    expect(
      tester.widget<ReadTab>(find.byType(ReadTab)).captures.single.id,
      'a1',
    );
    expect(find.textContaining('Finish the start photo'), findsOneWidget);
  });

  testWidgets('a failing recovery never stops the app', (tester) async {
    await api.captures.launching('a1', 'start');
    await pump(tester, lostPhoto: () async => throw const DavException('x', 0));
    expect(api.fetches, 1);
    expect(await api.errors.diagnostics(), contains('"stage":"camera"'));
  });

  testWidgets('leaving and returning to the app are logged', (tester) async {
    await pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    final events = [
      for (final n in await api.store.list('eventbox/'))
        if (n.endsWith('.body')) utf8.decode((await api.store.read(n))!),
    ];
    expect(events, [
      contains('"event":"paused"'),
      contains('"event":"resumed"'),
    ]);
  });
}
