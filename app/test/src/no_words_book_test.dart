/// The zero-text guard over the Book tab: its states, the finder and the
/// file panel.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/national_library.dart';
import 'package:book_guard_app/src/open_library.dart';
import 'package:book_guard_app/src/screens/book_file_panel.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_api.dart';
import '../support/finders_book.dart';
import '../support/library_api.dart';
import '../support/no_words_book_support.dart';
import '../support/states.dart';

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
      expectBookClean(tester);
    });

    testWidgets('with a bare book', (tester) async {
      await bookTab(
        tester,
        sampleState({
          'book': {'title': 'Cesarz'},
        }),
      );
      expectBookClean(tester);
    });

    testWidgets('with no book', (tester) async {
      await bookTab(tester, null);
      expectBookClean(tester);
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
        expectBookClean(tester);
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
      expectBookClean(tester);
      await bookTab(tester, null, docs: const {'docs': <Object>[]});
      await typeInto(tester, 'Title, e.g. Atomic Habits', 'Nothing');
      await tapLabeled(tester, 'Search');
      await settle(tester);
      expect(find.byIcon(Icons.search_off), findsOneWidget);
      expectBookClean(tester);
      await bookTab(tester, null, status: 503);
      await typeInto(tester, 'Title, e.g. Atomic Habits', 'Dune');
      await tapLabeled(tester, 'Search');
      await settle(tester);
      expect(cueOf(CueKind.error), findsOneWidget);
      expectBookClean(tester);
    });

    testWidgets('an empty search: a red field and a cue', (tester) async {
      await bookTab(tester, null);
      await tapLabeled(tester, 'Search');
      await settle(tester);
      expect(fieldIsRed(tester, 'Title, e.g. Atomic Habits'), isTrue);
      expectBookClean(tester);
    });

    testWidgets('a refused registration', (tester) async {
      api.onSend = (_) async =>
          const GuardResponse(ok: false, code: 'bad_isbn');
      await bookTab(tester, null);
      await typeInto(tester, 'ISBN (optional)', '123');
      await tester.tap(find.byIcon(Icons.library_add));
      await settle(tester);
      expectBookClean(tester);
    });

    testWidgets('the formats dialog', (tester) async {
      await bookTab(tester, sampleState());
      await tapLabeled(tester, 'Attach book file');
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expectBookClean(tester);
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
      expectBookClean(tester);
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
        expectBookClean(tester);
      }
    });
  });
}
