import 'dart:async';
import 'dart:convert';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/open_library.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/fake_api.dart';

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

void main() {
  late FakeApi api;
  late int changed;
  late List<Map<String, String>> queries;
  late Map<String, Object> docs;
  late int status;

  setUp(() {
    api = FakeApi();
    changed = 0;
    queries = [];
    docs = _docs;
    status = 200;
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
      bookSource: () async => null,
    ),
  );

  Finder field(String label) => find.widgetWithText(TextField, label);

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
    expect(
      find.text('None yet - search below, or photograph the barcode.'),
      findsOneWidget,
    );
    expect(find.text('Set'), findsNothing);
    expect(find.byIcon(Icons.attach_file), findsNothing);
  });

  testWidgets('search lists hits; a hit without ISBN is disabled', (
    tester,
  ) async {
    await pump(tester);
    await search(tester, '  Dune ');
    expect(queries.single['title'], 'Dune');
    expect(queries.single.containsKey('author'), isFalse);
    expect(
      find.text('Frank Herbert - 604 p - ISBN 9780441013593'),
      findsOneWidget,
    );
    expect(find.text('? - ? p - ISBN none'), findsOneWidget);
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
    expect(find.text('done register'), findsOneWidget);
    expect(find.text('Dune Notes'), findsNothing);
    expect(changed, 2);
  });

  testWidgets('a refused registration is shown as an error', (tester) async {
    api.onSend = (_) async =>
        const GuardResponse(ok: false, message: 'Unknown ISBN');
    await pump(tester);
    await search(tester, 'Dune');
    await tapVisible(tester, find.widgetWithText(ListTile, 'Dune'));
    await settle(tester);
    expect(find.text('Unknown ISBN'), findsOneWidget);
  });

  testWidgets('a failed search is shown, not thrown', (tester) async {
    status = 503;
    await pump(tester);
    await search(tester, 'Dune');
    expect(find.text('Exception: Open Library answered 503'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
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
    answer.complete(const GuardResponse(ok: true, message: 'late'));
    await settle(tester);
    expect(find.text('late'), findsNothing);
    expect(changed, 2);
  });

  testWidgets('the author field searches too, narrowing by author', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(field('Title, e.g. Atomic Habits'), 'Dune');
    await tester.enterText(field('Author (optional)'), ' Herbert ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(queries.single['author'], 'Herbert');
  });

  testWidgets('an empty title is refused without a request', (tester) async {
    await pump(tester);
    await tapVisible(tester, find.byIcon(Icons.search));
    await settle(tester);
    expect(find.text('Enter a title to search.'), findsOneWidget);
    expect(queries, isEmpty);
  });

  testWidgets('no hits says so, and a later hit clears it', (tester) async {
    docs = const {'docs': <Object>[]};
    await pump(tester);
    await search(tester, 'Czerwony Cesarz', author: 'Sheridan');
    expect(
      find.text("No books found for 'Czerwony Cesarz' - enter the ISBN below."),
      findsOneWidget,
    );
    docs = _docs;
    await search(tester, 'Dune');
    expect(find.textContaining('No books found'), findsNothing);
    expect(find.text('Dune Notes'), findsOneWidget);
  });

  testWidgets('a typed ISBN registers with the typed title and author', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(field('Title, e.g. Atomic Habits'), ' Cesarz ');
    await tester.enterText(field('Author (optional)'), 'Sheridan');
    await tester.enterText(field('ISBN (optional)'), ' 9788368380002 ');
    await tapVisible(tester, find.text('Register'));
    await settle(tester);
    expect(api.sent.single.type, 'register');
    expect(api.sent.single.body, {
      'isbn': '9788368380002',
      'title': 'Cesarz',
      'author': 'Sheridan',
    });
    expect(find.text('done register'), findsOneWidget);
    expect(queries, isEmpty);
  });

  test('every format the PC reads is pickable', () {
    expect(ebookExtensions, containsAll(['epub', 'pdf', 'mobi', 'azw3']));
  });
}
