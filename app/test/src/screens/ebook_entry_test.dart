import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/ebook_entry.dart';
import 'package:book_guard_app/src/screens/ebook_reader.dart';
import 'package:book_guard_app/src/screens/reading_settings.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/ebook_fixture.dart';
import '../../support/fake_api.dart';
import '../../support/finders_book.dart';
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
    expect(iconLabeled('Read in app'), findsNothing);
    await pump(tester, ebookState(reader: false));
    expect(iconLabeled('Read in app'), findsNothing);
    await pump(tester, GuardState.fromJson(const {}));
    expect(iconLabeled('Read in app'), findsNothing);
  });

  testWidgets('downloads the book and opens the reader', (tester) async {
    await pump(tester, ebookState(latestPage: 20));
    expect(iconLabeled('Read in app'), findsOneWidget);
    expect(find.text('≈ 20'), findsOneWidget);
    await tester.tap(iconLabeled('Read in app'));
    await tester.pumpAndSettle();
    expect(find.byType(EbookReaderScreen), findsOneWidget);
    await tester.binding.handlePopRoute(); // the system back
    await tester.pumpAndSettle();
    expect(find.byType(EbookReaderScreen), findsNothing);
    expect(changed, 1);
  });

  testWidgets('a download glyph shows the book is not downloaded yet', (
    tester,
  ) async {
    api.files.clear();
    await pump(tester, ebookState());
    expect(
      iconLabeled(
        'The book for in-app reading downloads when the PC is reachable',
      ),
      findsOneWidget,
    );
    expect(iconLabeled('Read in app'), findsNothing);
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
    expect(iconLabeled('Continue reading in app'), findsOneWidget);
    expect(iconLabeled('Read in app'), findsNothing);
    // The clock glyph and the start time (local) show beside the reader.
    expect(iconLabeled('Since'), findsOneWidget);
  });

  testWidgets('a stopped session asks for its summary at once', (tester) async {
    await keep(stopped());
    await pump(tester, ebookState());
    expect(find.byType(SummaryPanel), findsOneWidget);
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
    expect(find.byType(SummaryPanel), findsNothing);
    expect(await api.appSessions(), isEmpty);
  });

  testWidgets('a session the PC refused is dropped', (tester) async {
    await keep(stopped());
    final kept = (await api.appSessions()).single;
    await api.store.write('refused/${kept.requestId}', Uint8List(1));
    await pump(tester, ebookState());
    expect(find.byType(SummaryPanel), findsNothing);
    expect(await api.appSessions(), isEmpty);
  });

  testWidgets('a refusal arriving with a later refresh drops it too', (
    tester,
  ) async {
    await keep(stopped());
    await pump(tester, ebookState());
    expect(find.byType(SummaryPanel), findsOneWidget);
    final kept = (await api.appSessions()).single;
    await api.store.write('refused/${kept.requestId}', Uint8List(1));
    await pump(tester, ebookState()); // the same snapshot, fetched again
    expect(find.byType(SummaryPanel), findsNothing);
  });

  testWidgets('stopping in the reader shows the summary box', (tester) async {
    await pump(tester, ebookState(latestPage: 20));
    await tester.tap(iconLabeled('Read in app'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      await tester.pumpAndSettle();
    }
    now = now.add(const Duration(hours: 1));
    await tester.fling(
      find.byType(EbookReaderScreen),
      const Offset(-300, 0),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.byType(EbookReaderScreen), findsNothing);
    expect(find.byType(SummaryPanel), findsOneWidget);
    // The saved session is shown as a glyph and its page range.
    expect(cueGlyph(Icons.chrome_reader_mode), findsOneWidget);
    expect(
      find.descendant(
        of: cueGlyph(Icons.chrome_reader_mode),
        matching: find.textContaining('≈20-'),
      ),
      findsOneWidget,
    );
    expect(changed, 1);
  });

  testWidgets('the reading settings are a tap away', (tester) async {
    await pump(tester, ebookState(latestPage: 20));
    await tester.tap(iconLabeled('Reading settings'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingSettingsScreen), findsOneWidget);
  });
}
