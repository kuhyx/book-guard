import 'dart:async';
import 'dart:convert';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/national_library.dart';
import 'package:book_guard_app/src/open_library.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/fake_api.dart';
import '../../support/finders_book.dart';

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

Map<String, Object> _bnBib(String isbn) => {
  'isbnIssn': isbn,
  'marc': {
    'fields': [
      {
        '100': {
          'subfields': [
            {'a': 'F., Herbert'},
          ],
        },
      },
      {
        '245': {
          'subfields': [
            {'a': 'Czerwony cesarz'},
          ],
        },
      },
    ],
  },
};

void main() {
  late FakeApi api;
  late int changed;
  late List<Map<String, String>> queries;
  late Map<String, Object> docs;
  late int status;
  late List<Object> bibs;
  late int bnStatus;

  setUp(() {
    api = FakeApi();
    changed = 0;
    queries = [];
    docs = _docs;
    status = 200;
    bibs = [];
    bnStatus = 200;
  });

  Future<void> pump(WidgetTester tester) => pumpTab(
    tester,
    BookTab(
      api: api,
      state: null,
      onChanged: () async => changed++,
      library: OpenLibrary(
        client: MockClient((request) async {
          queries.add(request.url.queryParameters);
          return http.Response(jsonEncode(docs), status);
        }),
      ),
      nationalLibrary: NationalLibrary(
        web: false,
        client: MockClient(
          (_) async => http.Response(jsonEncode({'bibs': bibs}), bnStatus),
        ),
      ),
      bookSource: () async => null,
    ),
  );

  Finder field(String label) => inputLabeled(label);

  Future<void> search(
    WidgetTester tester,
    String title, {
    String author = '',
  }) async {
    await tester.enterText(field('Title, e.g. Atomic Habits'), title);
    await tester.enterText(field('Author (optional)'), author);
    await tapVisible(tester, find.byIcon(Icons.search));
    await settle(tester);
  }

  testWidgets('no book yet: only the search is offered', (tester) async {
    await pump(tester);
    expect(iconLabeled('No book yet'), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('search lists hits; a hit without ISBN is disabled', (
    tester,
  ) async {
    await pump(tester);
    await search(tester, '  Dune ');
    expect(queries.single['title'], 'Dune');
    expect(queries.single.containsKey('author'), isFalse);
    expect(find.text('Frank Herbert'), findsOneWidget);
    expect(find.text('604'), findsOneWidget);
    expect(find.text('9780441013593'), findsOneWidget);
    // The hit without an ISBN shows no ISBN number at all.
    expect(iconLabeled('ISBN'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.map((t) => t.enabled), [true, false]);
    expect(changed, 1);
  });

  testWidgets('the keyboard search action searches too', (tester) async {
    await pump(tester);
    await tester.enterText(field('Title, e.g. Atomic Habits'), 'Dune');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(queries.single['title'], 'Dune');
    expect(find.text('Dune Notes'), findsOneWidget);
  });

  testWidgets('tapping a hit registers it and clears the list', (tester) async {
    await pump(tester);
    await search(tester, 'Dune');
    await tapVisible(tester, find.widgetWithText(ListTile, 'Dune'));
    await settle(tester);
    expect(api.sent.single.type, 'register');
    expect(api.sent.single.body, {'isbn': '9780441013593', 'pages': 604});
    expect(cueGlyph(Icons.check_circle), findsOneWidget);
    expect(find.text('Dune Notes'), findsNothing);
    expect(changed, 2);
  });

  testWidgets('a refused registration is shown as an error', (tester) async {
    api.onSend = (_) async => const GuardResponse(ok: false, code: 'bad_isbn');
    await pump(tester);
    await search(tester, 'Dune');
    await tapVisible(tester, find.widgetWithText(ListTile, 'Dune'));
    await settle(tester);
    expect(cueGlyph(Icons.qr_code_2), findsOneWidget);
    expect(cueOf(CueKind.error), findsOneWidget);
  });

  testWidgets('both catalogues failing is shown, not thrown', (tester) async {
    status = 503;
    bnStatus = 500;
    await pump(tester);
    await search(tester, 'Dune');
    expect(cueOf(CueKind.error), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    // The reason is kept in the error log, not on screen.
    expect(
      await api.errors.diagnostics(),
      contains('Neither Open Library nor Biblioteka Narodowa answered'),
    );
  });

  testWidgets('one catalogue failing still shows the other', (tester) async {
    status = 503;
    bibs = [_bnBib('9788368380002')];
    await pump(tester);
    await search(tester, 'Czerwony cesarz');
    expect(find.text('Czerwony cesarz'), findsWidgets);
    expect(find.text('9788368380002'), findsOneWidget);
  });

  testWidgets('national hits come first; a repeated ISBN is listed once', (
    tester,
  ) async {
    bibs = [_bnBib('9780441013593')];
    await pump(tester);
    await search(tester, 'Dune');
    final titles = [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
        (tile.title! as Text).data,
    ];
    expect(titles.length, 2);
    expect(
      find.descendant(
        of: find.byType(ListTile).first,
        matching: find.text('Herbert F.'),
      ),
      findsOneWidget,
    );
    // Listed once: the repeated ISBN is shown for the national hit only.
    expect(find.text('9780441013593'), findsOneWidget);
  });

  testWidgets('a result arriving after the tab closed is dropped', (
    tester,
  ) async {
    final answer = Completer<GuardResponse>();
    api.onSend = (_) => answer.future;
    await pump(tester);
    await search(tester, 'Dune');
    await tapVisible(tester, find.widgetWithText(ListTile, 'Dune'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    answer.complete(const GuardResponse(ok: true, code: 'registered'));
    await settle(tester);
    expect(find.byType(StatusCue), findsNothing);
    expect(changed, 2);
  });
}
