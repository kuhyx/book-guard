/// The zero-text guard over a session, the connection settings and the
/// in-app reader.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/login_store.dart';
import 'package:book_guard_app/src/screens/ebook_entry.dart';
import 'package:book_guard_app/src/screens/reading_settings.dart';
import 'package:book_guard_app/src/screens/session_screen.dart';
import 'package:book_guard_app/src/screens/session_times.dart';
import 'package:book_guard_app/src/screens/settings_screen.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/ebook_fixture.dart';
import '../support/fake_api.dart';
import '../support/finders_book.dart';
import '../support/no_words_book_support.dart';
import '../support/reader_harness.dart';

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  group('session detail', () {
    const session = SessionInfo(
      id: 's1',
      startPage: 7,
      endPage: 51,
      checkPage: 19,
      pages: 44,
      minutes: 43,
      status: 'credited',
      startedAt: null,
      detail: 'sessions/s1.json',
    );

    Uint8List json(Object value) =>
        Uint8List.fromList(utf8.encode(jsonEncode(value)));

    testWidgets('with photos, a summary and the grader', (tester) async {
      api.files['sessions/s1.json'] = json({
        'book': 'Czerwony cesarz',
        'photos': [
          {
            'role': 'start',
            'page': 7,
            'file': 'processed/a.jpg',
            'thumb': 'thumbs/a.jpg',
            'text': 'KRÓTKI PRZEWODNIK',
          },
          {'role': 'end', 'file': 'processed/b.jpg', 'thumb': 'thumbs/b.jpg'},
        ],
        'summary': 'Xi was born in 1953.',
        'feedback': 'Specific and consistent.',
      });
      await pumpScreen(tester, SessionScreen(api: api, session: session));
      expectBookClean(tester);
      await tester.tap(iconLabeled('start').last);
      await tester.pumpAndSettle();
      expectBookClean(tester);
    });

    testWidgets('with no summary, and with no details file', (tester) async {
      api.files['sessions/s1.json'] = json({'status': 'needs-quiz'});
      await pumpScreen(tester, SessionScreen(api: api, session: session));
      expectBookClean(tester);
      api.files.clear();
      await pumpScreen(tester, SessionScreen(api: api, session: session));
      expectBookClean(tester);
    });

    testWidgets('the times line, graded and not', (tester) async {
      for (final status in ['needs-quiz', 'credited']) {
        await pumpTab(
          tester,
          SessionTimes(
            api: api,
            session: SessionInfo.fromJson({
              'id': 'x',
              'status': status,
              'start_page': 1,
              'end_page': 9,
              'minutes': 30,
              'started_at': '2026-10-03T12:27:38',
              'ended_at': '2026-10-03T12:57:38',
              'photo_start': '2026-10-03T12:27:38',
            }),
            onChanged: () async {},
          ),
        );
        expectBookClean(tester);
      }
    });
  });

  group('settings', () {
    setUp(
      () => FlutterSecureStorage.setMockInitialValues({
        'dufs_url': 'https://old.host',
        'dufs_user': 'bookguard',
        'dufs_password': 'old',
      }),
    );

    testWidgets('the connection, filled, then refused with a field empty', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        SettingsScreen(store: LoginStore(), onSaved: () async {}, api: api),
      );
      expectBookClean(tester);
      await tester.enterText(inputLabeled('Password'), '');
      await tapLabeled(tester, 'Save');
      await settle(tester);
      expect(fieldIsRed(tester, 'Password'), isTrue);
      expectBookClean(tester);
    });

    testWidgets('the first run has no reading entry', (tester) async {
      await pumpScreen(
        tester,
        SettingsScreen(store: LoginStore(), onSaved: () async {}),
      );
      expectBookClean(tester);
    });

    testWidgets('the reading settings, with the preview line', (tester) async {
      await pumpScreen(tester, ReadingSettingsScreen(api: api));
      expectBookClean(tester);
    });
  });

  group('in-app reading', () {
    Future<void> entry(
      WidgetTester tester,
      GuardState state, {
      Map<String, Uint8List>? files,
    }) async {
      api = FakeApi()..files.addAll(files ?? ebookFiles());
      await pumpTab(
        tester,
        ListView(
          children: [
            EbookEntry(
              key: UniqueKey(),
              api: api,
              state: state,
              onChanged: () async {},
            ),
          ],
        ),
      );
      await settle(tester);
    }

    testWidgets('the entry button, not yet downloaded and a running start', (
      tester,
    ) async {
      await entry(tester, ebookState(latestPage: 20));
      expect(iconLabeled('Read in app'), findsOneWidget);
      expectBookClean(tester);
      await entry(tester, ebookState(), files: {});
      expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
      expectBookClean(tester);
    });

    testWidgets('the reader and its cues', (tester) async {
      api = FakeApi()..files.addAll(ebookFiles());
      final ebook = (await api.syncEbook(
        ebookIsbn,
        ebookState().book!.ebook!,
      ))!;
      final reader = ReaderHarness(api, ebook, DateTime.utc(2026, 10, 23, 18));
      await reader.open(tester, latestPage: 20, paperStart: 18);
      expect(find.byType(StatusCue), findsOneWidget);
      expectBookClean(tester);
    });
  });
}
