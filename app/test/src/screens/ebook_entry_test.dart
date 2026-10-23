import 'dart:typed_data';

import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/ebook_entry.dart';
import 'package:book_guard_app/src/screens/ebook_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ebook_fixture.dart';
import '../../support/fake_api.dart';
import '../../support/states.dart';

void main() {
  late FakeApi api;
  late int changed;
  late DateTime now;

  setUp(() {
    api = FakeApi()..files.addAll(ebookFiles());
    changed = 0;
    now = DateTime.utc(2026, 10, 23, 18);
  });

  Future<void> pump(
    WidgetTester tester,
    GuardState state, {
    int? paperStart,
  }) async {
    await pumpTab(
      tester,
      ListView(
        children: [
          EbookEntry(
            api: api,
            state: state,
            paperStart: paperStart,
            onChanged: () async => changed++,
            clock: () => now,
          ),
        ],
      ),
    );
    await settle(tester);
  }

  AppSession stopped({String key = 'abcdef0123456789'}) => AppSession(
    key: key,
    requestId: 'req$key',
    startPage: 20,
    endPage: 25,
    startedAt: DateTime.utc(2026, 10, 23, 18),
    endedAt: DateTime.utc(2026, 10, 23, 19),
  );

  Future<void> keep(AppSession session) async {
    final map = EbookMap.fromJson(ebookMapJson())!;
    final start = ReadingStart(
      id: session.key,
      isbn: ebookIsbn,
      offset: map.offsetAt(session.startPage),
      startedAt: session.startedAt,
      textSha: shaOf(ebookText),
    );
    await api.stopReading(
      start,
      map.offsetAt(session.endPage),
      map,
      session.endedAt,
    );
  }

  testWidgets('nothing without a page map', (tester) async {
    await pump(tester, sampleState());
    expect(find.textContaining('Read in app'), findsNothing);
    await pump(tester, ebookState(reader: false));
    expect(find.textContaining('Read in app'), findsNothing);
    await pump(tester, GuardState.fromJson(const {}));
    expect(find.textContaining('Read in app'), findsNothing);
  });

  testWidgets('downloads the book and opens the reader', (tester) async {
    await pump(tester, ebookState(latestPage: 20));
    expect(find.text('Read in app (≈ p. 20)'), findsOneWidget);
    await tester.tap(find.text('Read in app (≈ p. 20)'));
    await tester.pumpAndSettle();
    expect(find.byType(EbookReaderScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(changed, 1);
  });

  testWidgets('says when the book is not downloaded yet', (tester) async {
    api.files.clear();
    await pump(tester, ebookState());
    expect(find.textContaining('when the PC is reachable'), findsOneWidget);
  });

  testWidgets('a running session is continued', (tester) async {
    await api.startReading(
      ReadingStart(
        id: 'abcdef0123456789',
        isbn: ebookIsbn,
        offset: 0,
        startedAt: DateTime.utc(2026, 10, 23, 18),
        textSha: shaOf(ebookText),
      ),
    );
    await pump(tester, ebookState());
    expect(find.textContaining('Continue reading in app'), findsOneWidget);
  });

  testWidgets('a stopped session asks for its summary at once', (tester) async {
    await keep(stopped());
    await pump(tester, ebookState());
    expect(find.text('Summary for ≈ p. 20-25'), findsOneWidget);
    // Once the PC lists it, the Read tab's own summary panel has it.
    await pump(
      tester,
      ebookState(
        sessions: [
          {
            'id': 'session:ebook-abcdef0123456789',
            'status': 'needs-quiz',
            'start_page': 20,
            'end_page': 25,
            'estimated': true,
          },
        ],
      ),
    );
    expect(find.text('Summary for ≈ p. 20-25'), findsNothing);
    expect(await api.appSessions(), isEmpty);
  });

  testWidgets('a session the PC refused is dropped', (tester) async {
    await keep(stopped());
    final kept = (await api.appSessions()).single;
    await api.store.write('refused/${kept.requestId}', Uint8List(1));
    await pump(tester, ebookState());
    expect(find.text('Summary for ≈ p. 20-25'), findsNothing);
    expect(await api.appSessions(), isEmpty);
  });

  testWidgets('a refusal arriving with a later refresh drops it too', (
    tester,
  ) async {
    await keep(stopped());
    await pump(tester, ebookState());
    expect(find.text('Summary for ≈ p. 20-25'), findsOneWidget);
    final kept = (await api.appSessions()).single;
    await api.store.write('refused/${kept.requestId}', Uint8List(1));
    await pump(tester, ebookState()); // the same snapshot, fetched again
    expect(find.text('Summary for ≈ p. 20-25'), findsNothing);
  });

  testWidgets('stopping in the reader shows the summary box', (tester) async {
    await pump(tester, ebookState(latestPage: 20));
    await tester.tap(find.text('Read in app (≈ p. 20)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start reading here'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
    }
    now = now.add(const Duration(hours: 1));
    await tester.tap(find.text('Stop reading'));
    await tester.pumpAndSettle();
    expect(find.byType(EbookReaderScreen), findsNothing);
    expect(find.textContaining('Summary for ≈ p. 20-'), findsOneWidget);
    expect(changed, 1);
  });
}
