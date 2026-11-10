import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_read.dart';

JournalEntry _entry(String name, String label) => JournalEntry(
  name: name,
  label: label,
  sha: 'f' * 64,
  takenAt: DateTime.utc(2026, 10, 3, 12, 27),
);

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  // A fresh widget over the same store is what an app restart looks like.
  Future<void> pump(WidgetTester tester, List<JournalEntry> journal) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTab(
      tester,
      SingleChildScrollView(
        child: FailedPhotos(
          key: UniqueKey(),
          api: api,
          state: GuardState.fromJson(const {}),
          journal: journal,
          onChanged: () async {},
        ),
      ),
    );
    await settle(tester, 10);
  }

  testWidgets('dismiss hides one card, persisted across restarts', (
    tester,
  ) async {
    final journal = [
      _entry('stop_a.jpg', 'stop'),
      _entry('stop_b.jpg', 'stop'),
    ];
    await pump(tester, journal);
    expect(spoken('Dismiss'), findsNWidgets(2));
    final before = (await api.store.list('')).toSet();
    // Newest first: the first card is stop_b.
    await tester.tap(spoken('Dismiss').first);
    await settle(tester, 10);
    expect(spoken('Dismiss'), findsOneWidget);
    expect(spoken('failed photos'), findsOneWidget);
    expect(await api.dismissedPhotos(), {'stop_b.jpg'});
    // Hide-only: one marker is added, nothing else on the device changes
    // and nothing is queued for the PC.
    expect((await api.store.list('')).toSet().difference(before), {
      'dismissed/stop_b.jpg',
    });
    expect(before.difference((await api.store.list('')).toSet()), isEmpty);
    expect(await api.store.list('outbox/'), isEmpty);

    await pump(tester, journal);
    expect(spoken('Dismiss'), findsOneWidget);
  });

  testWidgets('clear all hides the section; a new failure still shows', (
    tester,
  ) async {
    final journal = [
      _entry('stop_a.jpg', 'stop'),
      _entry('stop_b.jpg', 'stop'),
    ];
    await pump(tester, journal);
    // One tap does nothing: hiding every card needs a hold.
    await tester.tap(find.byIcon(Icons.clear_all));
    await settle(tester, 10);
    expect(await api.dismissedPhotos(), isEmpty);
    await hold(tester, find.byIcon(Icons.clear_all));
    await settle(tester, 10);
    expect(spoken('failed photos'), findsNothing);
    expect(await api.dismissedPhotos(), {'stop_a.jpg', 'stop_b.jpg'});

    await pump(tester, journal);
    expect(spoken('failed photos'), findsNothing);

    await pump(tester, [...journal, _entry('stop_c.jpg', 'stop')]);
    expect(spoken('failed photos'), findsOneWidget);
    expect(spoken('Dismiss'), findsOneWidget);
    expect(rejected(RejectGlyph.noNumber), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });
}
