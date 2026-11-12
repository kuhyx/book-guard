/// The zero-text guard over group C: the Book tab, the finder, the file
/// panel, the edit form, the library, a session's detail, the connection
/// settings and the in-app reader, in every state a screen can be in.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/book_formats.dart';
import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/login_store.dart';
import 'package:book_guard_app/src/national_library.dart';
import 'package:book_guard_app/src/open_library.dart';
import 'package:book_guard_app/src/screens/book_file_panel.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:book_guard_app/src/screens/ebook_entry.dart';
import 'package:book_guard_app/src/screens/edit_book_screen.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:book_guard_app/src/screens/library_tab.dart';
import 'package:book_guard_app/src/screens/reading_settings.dart';
import 'package:book_guard_app/src/screens/session_screen.dart';
import 'package:book_guard_app/src/screens/session_times.dart';
import 'package:book_guard_app/src/screens/settings_screen.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:design_system/design_system.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../support/ebook_fixture.dart';
import '../support/fake_api.dart';
import '../support/fake_share.dart';
import '../support/finders_book.dart';
import '../support/library_api.dart';
import '../support/library_json.dart';
import '../support/no_words.dart';
import '../support/reader_harness.dart';
import '../support/states.dart';

/// Text the reader or the book wrote, file names and format identifiers:
/// shown as they are.
final content = <String>[
  'Atomic Habits', 'James Clear', 'Cesarz', 'Wstęp', 'Wstep', 'Jeden', //
  'Done Book', 'Next Book', 'Dune', 'Frank Herbert', 'Dune Notes', //
  'Czerwony cesarz', 'Zbrodnia i kara', 'Sheridan', 'Herbert F.', //
  'a.epub', 'a.mobi', 'Atomic.epub', 'movie.mkv', 'from the PC', //
  'first try', 'second try', 'mention the habit loop', 'good', 'mine', //
  'KRÓTKI PRZEWODNIK', 'Xi was born in 1953.', 'Specific and consistent.', //
  'Michael S.', 'Rozdział 1', 'bookguard', 'https://old.host', //
  'Paragraph', 'word', //
  for (final e in bookExtensions) '.$e',
];

const Map<String, Object> _docs = {
  'docs': [
    {
      'title': 'Dune',
      'author_name': ['Frank Herbert'],
      'number_of_pages_median': 604,
      'isbn': ['9780441013593'],
    },
    {'title': 'Dune Notes'},
  ],
};

Map<String, dynamic> _job(String stage, {String? updatedAt, String? error}) => {
  'index_job': {
    'file': 'a.epub',
    'stage': stage,
    'done': 2,
    'total': 8,
    'error': error ?? '',
    'updated_at': updatedAt ?? DateTime.now().toUtc().toIso8601String(),
  },
};

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> bookTab(
    WidgetTester tester,
    GuardState? state, {
    Object docs = _docs,
    int status = 200,
  }) async {
    tallSurface(tester);
    await pumpTab(
      tester,
      BookTab(
        key: UniqueKey(),
        api: api,
        state: state,
        onChanged: () async {},
        library: OpenLibrary(
          client: MockClient(
            (_) async => http.Response(jsonEncode(docs), status),
          ),
        ),
        nationalLibrary: NationalLibrary(
          web: false,
          client: MockClient(
            (_) async => http.Response(jsonEncode({'bibs': <Object>[]}), 500),
          ),
        ),
        bookSource: () async => null,
      ),
    );
    await settle(tester);
  }

  Future<void> screen(WidgetTester tester, Widget home) async {
    tallSurface(tester);
    await tester.pumpWidget(MaterialApp(theme: buildLightTheme(), home: home));
    await settle(tester);
  }

  void clean(WidgetTester tester) => expectNoWords(tester, content: content);

  group('book tab', () {
    testWidgets('with a book, a chapter and an ebook', (tester) async {
      await bookTab(
        tester,
        sampleState({
          'book': {
            'isbn': '9780735211292',
            'title': 'Atomic Habits',
            'author': 'James Clear',
            'pages': 320,
            'has_file': true,
            'chapters': [
              {'start': 9, 'title': 'Wstęp'},
            ],
            'chapter': {'number': 1, 'of': 1, 'title': 'Wstęp'},
          },
        }),
      );
      clean(tester);
    });

    testWidgets('with a bare book', (tester) async {
      await bookTab(
        tester,
        sampleState({
          'book': {'title': 'Cesarz'},
        }),
      );
      clean(tester);
    });

    testWidgets('with no book', (tester) async {
      await bookTab(tester, null);
      clean(tester);
    });

    for (final (name, job) in [
      ('uploaded', _job('uploaded')),
      ('extracting', _job('extracting')),
      ('embedding', _job('embedding')),
      ('done', _job('done')),
      ('failed', _job('failed', error: 'a.epub: no text layer')),
      ('stalled', _job('embedding', updatedAt: '2026-01-01T00:00:00Z')),
    ]) {
      testWidgets('index job $name', (tester) async {
        await bookTab(tester, sampleState(job));
        clean(tester);
      });
    }

    testWidgets('the finder: hits, then a miss, then both catalogues down', (
      tester,
    ) async {
      await bookTab(tester, null);
      await typeInto(tester, 'Title, e.g. Atomic Habits', 'Dune');
      await tapLabeled(tester, 'Search');
      await settle(tester);
      expect(find.text('Dune Notes'), findsOneWidget);
      clean(tester);
      await bookTab(tester, null, docs: const {'docs': <Object>[]});
      await typeInto(tester, 'Title, e.g. Atomic Habits', 'Nothing');
      await tapLabeled(tester, 'Search');
      await settle(tester);
      expect(find.byIcon(Icons.search_off), findsOneWidget);
      clean(tester);
      await bookTab(tester, null, status: 503);
      await typeInto(tester, 'Title, e.g. Atomic Habits', 'Dune');
      await tapLabeled(tester, 'Search');
      await settle(tester);
      expect(cueOf(CueKind.error), findsOneWidget);
      clean(tester);
    });

    testWidgets('an empty search: a red field and a cue', (tester) async {
      await bookTab(tester, null);
      await tapLabeled(tester, 'Search');
      await settle(tester);
      expect(fieldIsRed(tester, 'Title, e.g. Atomic Habits'), isTrue);
      clean(tester);
    });

    testWidgets('a refused registration', (tester) async {
      api.onSend = (_) async =>
          const GuardResponse(ok: false, code: 'bad_isbn');
      await bookTab(tester, null);
      await typeInto(tester, 'ISBN (optional)', '123');
      await tester.tap(find.byIcon(Icons.library_add));
      await settle(tester);
      clean(tester);
    });

    testWidgets('the formats dialog', (tester) async {
      await bookTab(tester, sampleState());
      await tapLabeled(tester, 'Attach book file');
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      clean(tester);
    });

    testWidgets('an unreadable file', (tester) async {
      tallSurface(tester);
      await pumpTab(
        tester,
        BookTab(
          api: api,
          state: sampleState(),
          onChanged: () async {},
          bookSource: () async =>
              XFile.fromData(Uint8List(1), path: '/b/movie.mkv'),
        ),
      );
      await tapLabeled(tester, 'Attach book file');
      await settle(tester);
      await tester.tap(iconLabeled('Choose file'));
      await settle(tester);
      expect(find.text('movie.mkv'), findsOneWidget);
      clean(tester);
    });

    testWidgets('the file panel card alone, every stage', (tester) async {
      for (final stage in [
        'uploaded',
        'extracting',
        'embedding',
        'done',
        'failed',
        'odd',
      ]) {
        await pumpTab(
          tester,
          IndexJobCard(
            job: IndexJob(
              file: 'a.epub',
              stage: stage,
              done: 1,
              total: 4,
              error: 'a.epub: no text layer',
              updatedAt: DateTime.now(),
            ),
            onRetry: () {},
          ),
        );
        clean(tester);
      }
    });
  });

  group('edit book', () {
    const book = BookInfo(
      isbn: '9788368380002',
      title: 'Cesarz',
      author: 'Sheridan',
      pages: 406,
      hasFile: false,
      chapters: [ChapterInfo(start: 9, title: 'Wstęp')],
    );

    testWidgets('the form, an added chapter, a refused page count', (
      tester,
    ) async {
      api.onSend = (_) async =>
          const GuardResponse(ok: false, code: 'bad_pages');
      await screen(tester, EditBookScreen(api: api, book: book));
      clean(tester);
      await tapLabeled(tester, 'Add chapter');
      await tester.pump();
      clean(tester);
      await tapLabeled(tester, 'Save');
      await settle(tester);
      expect(fieldIsRed(tester, 'Last page of your copy'), isTrue);
      clean(tester);
    });

    testWidgets('after a lookup', (tester) async {
      api.onSend = (_) async => const GuardResponse(
        ok: true,
        code: 'found',
        data: {'title': 'Czerwony cesarz', 'author': 'Michael S.', 'pages': 4},
      );
      await screen(tester, EditBookScreen(api: api, book: book));
      await tapLabeled(tester, 'Fill from ISBN');
      await settle(tester);
      clean(tester);
    });
  });

  group('library', () {
    late FakeShare share;

    setUp(() => share = FakeShare());

    testWidgets('empty', (tester) async {
      await screen(
        tester,
        Scaffold(body: LibraryTab(api: libraryApi(share), state: null)),
      );
      clean(tester);
    });

    testWidgets('with books', (tester) async {
      putLibrary(share, libraryJson());
      await screen(
        tester,
        Scaffold(body: LibraryTab(api: libraryApi(share), state: null)),
      );
      clean(tester);
    });

    Future<void> openBook(
      WidgetTester tester,
      int index, {
      GuardState? state,
    }) async {
      putLibrary(share, libraryJson());
      share.files['Reading/thumbs/p.jpg'] = tinyPng;
      final books = Library.fromJson(libraryJson()).books;
      await screen(
        tester,
        LibraryBookScreen(
          api: libraryApi(share),
          book: books[index],
          state: state,
        ),
      );
    }

    testWidgets('a book with notes, chapters and sessions expanded', (
      tester,
    ) async {
      await openBook(tester, 0);
      clean(tester);
      await tester.tap(find.text('02.10.2026'));
      await tester.pumpAndSettle();
      expect(find.text('second try'), findsOneWidget);
      clean(tester);
      await tester.tap(iconLabeled('Failed'));
      await tester.pumpAndSettle();
      expect(find.text('first try'), findsOneWidget);
      clean(tester);
    });

    testWidgets('a finished book and an empty one', (tester) async {
      await openBook(tester, 1);
      clean(tester);
      await openBook(tester, 2);
      clean(tester);
    });

    testWidgets('the note editor, new, filled and refused empty', (
      tester,
    ) async {
      await openBook(tester, 0);
      await tester.tap(iconLabeled('Add a note'));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsWidgets);
      clean(tester);
      await tester.tap(iconLabeled('Save'));
      await tester.pumpAndSettle();
      expect(fieldIsRed(tester, 'Note'), isTrue);
      clean(tester);
      await typeInto(tester, 'Note', 'mine');
      await typeInto(tester, 'Page (optional)', '12');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Jeden'));
      await tester.pump();
      clean(tester);
      await tester.tap(iconLabeled('Save'));
      await tester.pumpAndSettle();
      // The saved-on-the-device cue and the queued marker.
      expect(iconLabeled('Queued: not on the PC yet'), findsOneWidget);
      clean(tester);
    });

    testWidgets('the switch confirmation dialog', (tester) async {
      api.offline = true;
      final books = Library.fromJson(libraryJson()).books;
      await screen(
        tester,
        LibraryBookScreen(
          api: api,
          book: books[1],
          state: readingState(openStart: 12),
        ),
      );
      await tester.tap(iconLabeled('Read this now'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      clean(tester);
    });
  });

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
      await screen(tester, SessionScreen(api: api, session: session));
      clean(tester);
      await tester.tap(iconLabeled('start').last);
      await tester.pumpAndSettle();
      clean(tester);
    });

    testWidgets('with no summary, and with no details file', (tester) async {
      api.files['sessions/s1.json'] = json({'status': 'needs-quiz'});
      await screen(tester, SessionScreen(api: api, session: session));
      clean(tester);
      api.files.clear();
      await screen(tester, SessionScreen(api: api, session: session));
      clean(tester);
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
        clean(tester);
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
      await screen(
        tester,
        SettingsScreen(store: LoginStore(), onSaved: () async {}, api: api),
      );
      clean(tester);
      await tester.enterText(inputLabeled('Password'), '');
      await tapLabeled(tester, 'Save');
      await settle(tester);
      expect(fieldIsRed(tester, 'Password'), isTrue);
      clean(tester);
    });

    testWidgets('the first run has no reading entry', (tester) async {
      await screen(
        tester,
        SettingsScreen(store: LoginStore(), onSaved: () async {}),
      );
      clean(tester);
    });

    testWidgets('the reading settings, with the preview line', (tester) async {
      await screen(tester, ReadingSettingsScreen(api: api));
      clean(tester);
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
      clean(tester);
      await entry(tester, ebookState(), files: {});
      expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
      clean(tester);
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
      clean(tester);
    });
  });
}
