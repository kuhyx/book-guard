import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/edit_book_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

const _book = BookInfo(
  isbn: '9788368380002',
  title: 'Cesarz',
  author: 'Sheridan',
  pages: 406,
  hasFile: false,
  chapters: [ChapterInfo(start: 9, title: 'Wstęp')],
);

void main() {
  late FakeApi api;
  late List<bool?> popped;

  setUp(() {
    api = FakeApi();
    popped = [];
  });

  /// Opens the form over a home page that records what it pops with.
  Future<void> open(WidgetTester tester, {BookInfo book = _book}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => popped.add(
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => EditBookScreen(api: api, book: book),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('starts from the book as registered', (tester) async {
    await open(tester);
    expect(find.text('Cesarz'), findsOneWidget);
    expect(find.text('Sheridan'), findsOneWidget);
    expect(find.text('9788368380002'), findsOneWidget);
    expect(find.text('406'), findsOneWidget);
    expect(find.text('Wstęp'), findsOneWidget);
  });

  testWidgets('Save sends every field and the chapters, then pops', (
    tester,
  ) async {
    await open(tester);
    await tapVisible(tester, find.text('Add chapter'));
    await tester.pump();
    await tester.enterText(field('Chapter 2'), ' Rozdział 1 ');
    await tester.enterText(field('Page').last, '25');
    await tapVisible(tester, find.text('Add chapter'));
    await tester.pump();
    await tester.enterText(field('Chapter 3'), 'no page');
    await tapVisible(tester, find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.sent.single.type, 'edit_book');
    expect(api.sent.single.body, {
      'title': 'Cesarz',
      'author': 'Sheridan',
      'isbn': '9788368380002',
      'pages': '406',
      'chapters': [
        {'start': 9, 'title': 'Wstęp'},
        {'start': 25, 'title': 'Rozdział 1'},
      ],
    });
    expect(find.text('done edit_book'), findsOneWidget);
    expect(popped, [true]);
  });

  testWidgets('a chapter can be removed', (tester) async {
    await open(tester);
    await tapVisible(tester, find.byTooltip('Remove chapter'));
    await tester.pump();
    expect(find.text('Wstęp'), findsNothing);
    await tapVisible(tester, find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.sent.single.body['chapters'], isEmpty);
  });

  testWidgets('a refused save stays open and shows why', (tester) async {
    api.onSend = (_) async =>
        const GuardResponse(ok: false, message: 'Bad ISBN');
    await open(tester);
    await tapVisible(tester, find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Bad ISBN'), findsOneWidget);
    expect(find.text('Edit book'), findsOneWidget);
    expect(popped, isEmpty);
  });

  testWidgets('Fill from ISBN puts the lookup into the form', (tester) async {
    api.onSend = (_) async => const GuardResponse(
      ok: true,
      message: 'Found: Czerwony cesarz, 406 p',
      data: {'title': 'Czerwony cesarz', 'author': 'Michael S.', 'pages': 410},
    );
    const bare = BookInfo(
      isbn: '9788368380002',
      title: 'ISBN 9788368380002',
      author: '',
      pages: null,
      hasFile: false,
    );
    await open(tester, book: bare);
    await tapVisible(tester, find.text('Fill from ISBN'));
    await tester.pumpAndSettle();
    expect(api.sent.single.type, 'lookup');
    expect(api.sent.single.body, {'isbn': '9788368380002'});
    expect(find.text('Czerwony cesarz'), findsOneWidget);
    expect(find.text('Michael S.'), findsOneWidget);
    expect(find.text('410'), findsOneWidget);
    expect(
      find.text('Found: Czerwony cesarz, 406 p - review, then Save.'),
      findsOneWidget,
    );
  });

  testWidgets('empty lookup fields leave the form alone', (tester) async {
    api.onSend = (_) async => const GuardResponse(
      ok: true,
      message: 'Found',
      data: {'title': '', 'pages': null},
    );
    await open(tester);
    await tapVisible(tester, find.text('Fill from ISBN'));
    await tester.pumpAndSettle();
    expect(find.text('Cesarz'), findsOneWidget);
    expect(find.text('Sheridan'), findsOneWidget);
    expect(find.text('406'), findsOneWidget);
  });

  testWidgets('a failed lookup is shown', (tester) async {
    api.onSend = (_) async =>
        const GuardResponse(ok: false, message: 'No source knows it');
    await open(tester);
    await tapVisible(tester, find.text('Fill from ISBN'));
    await tester.pumpAndSettle();
    expect(find.text('No source knows it'), findsOneWidget);
  });

  testWidgets('an exception from the PC is shown, not thrown', (tester) async {
    api.onSend = (_) async => throw shareDown();
    await open(tester);
    await tapVisible(tester, find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('dufs Reading/x failed (500)'), findsOneWidget);
  });

  testWidgets('answers arriving after the form closed are dropped', (
    tester,
  ) async {
    final answer = Completer<GuardResponse>();
    api.onSend = (_) => answer.future;
    for (final button in ['Fill from ISBN', 'Save']) {
      await open(tester);
      await tapVisible(tester, find.text(button));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    answer.complete(const GuardResponse(ok: true, message: 'late'));
    await tester.pumpAndSettle();
    expect(find.text('late'), findsNothing);
  });
}
