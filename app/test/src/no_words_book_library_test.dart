/// The zero-text guard over the edit form and the library.
library;

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/screens/edit_book_screen.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:book_guard_app/src/screens/library_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_api.dart';
import '../support/fake_share.dart';
import '../support/finders_book.dart';
import '../support/library_api.dart';
import '../support/library_json.dart';
import '../support/no_words_book_support.dart';
import '../support/states.dart';

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

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
      await pumpScreen(tester, EditBookScreen(api: api, book: book));
      expectBookClean(tester);
      await tapLabeled(tester, 'Add chapter');
      await tester.pump();
      expectBookClean(tester);
      await tapLabeled(tester, 'Save');
      await settle(tester);
      expect(fieldIsRed(tester, 'Last page of your copy'), isTrue);
      expectBookClean(tester);
    });

    testWidgets('after a lookup', (tester) async {
      api.onSend = (_) async => const GuardResponse(
        ok: true,
        code: 'found',
        data: {'title': 'Czerwony cesarz', 'author': 'Michael S.', 'pages': 4},
      );
      await pumpScreen(tester, EditBookScreen(api: api, book: book));
      await tapLabeled(tester, 'Fill from ISBN');
      await settle(tester);
      expectBookClean(tester);
    });
  });

  group('library', () {
    late FakeShare share;

    setUp(() => share = FakeShare());

    testWidgets('empty', (tester) async {
      await pumpScreen(
        tester,
        Scaffold(body: LibraryTab(api: libraryApi(share), state: null)),
      );
      expectBookClean(tester);
    });

    testWidgets('with books', (tester) async {
      putLibrary(share, libraryJson());
      await pumpScreen(
        tester,
        Scaffold(body: LibraryTab(api: libraryApi(share), state: null)),
      );
      expectBookClean(tester);
    });

    Future<void> openBook(
      WidgetTester tester,
      int index, {
      GuardState? state,
    }) async {
      putLibrary(share, libraryJson());
      share.files['Reading/thumbs/p.jpg'] = tinyPng;
      final books = Library.fromJson(libraryJson()).books;
      await pumpScreen(
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
      expectBookClean(tester);
      await tester.tap(find.text('02.10.2026'));
      await tester.pumpAndSettle();
      expect(find.text('second try'), findsOneWidget);
      expectBookClean(tester);
      await tester.tap(iconLabeled('Failed'));
      await tester.pumpAndSettle();
      expect(find.text('first try'), findsOneWidget);
      expectBookClean(tester);
    });

    testWidgets('a finished book and an empty one', (tester) async {
      await openBook(tester, 1);
      expectBookClean(tester);
      await openBook(tester, 2);
      expectBookClean(tester);
    });

    testWidgets('the note editor, new, filled and refused empty', (
      tester,
    ) async {
      await openBook(tester, 0);
      await tester.tap(iconLabeled('Add a note'));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsWidgets);
      expectBookClean(tester);
      await tester.tap(iconLabeled('Save'));
      await tester.pumpAndSettle();
      expect(fieldIsRed(tester, 'Note'), isTrue);
      expectBookClean(tester);
      await typeInto(tester, 'Note', 'mine');
      await typeInto(tester, 'Page (optional)', '12');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Jeden'));
      await tester.pump();
      expectBookClean(tester);
      await tester.tap(iconLabeled('Save'));
      await tester.pumpAndSettle();
      // The saved-on-the-device cue and the queued marker.
      expect(iconLabeled('Queued: not on the PC yet'), findsOneWidget);
      expectBookClean(tester);
    });

    testWidgets('the switch confirmation dialog', (tester) async {
      api.offline = true;
      final books = Library.fromJson(libraryJson()).books;
      await pumpScreen(
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
      expectBookClean(tester);
    });
  });
}
