import 'dart:convert';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/fake_share.dart';
import '../../support/library_api.dart';
import '../../support/library_json.dart';

void main() {
  late FakeShare share;
  late GuardApi api;
  late List<LibraryBook> books;

  setUp(() {
    share = FakeShare();
    api = libraryApi(share);
    books = Library.fromJson(libraryJson()).books;
  });

  Future<void> pump(WidgetTester tester, LibraryBook book) async {
    tallSurface(tester);
    await pumpTab(tester, LibraryBookScreen(api: api, book: book));
    await settle(tester);
  }

  Future<void> expand(WidgetTester tester, String text) async {
    await tester.tap(find.textContaining(text));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the book, its notes, chapters and sessions', (
    tester,
  ) async {
    await pump(tester, books.first);
    expect(find.text('James Clear'), findsOneWidget);
    expect(
      find.text('p. 81/320 - 80 pages credited - in progress'),
      findsOneWidget,
    );
    expect(find.text('from the PC'), findsOneWidget);
    expect(find.text('3.10.2026 - p. 12 - Jeden'), findsOneWidget);
    expect(find.text('p. 9: Wstep'), findsOneWidget);
    expect(find.text('p. 25: Jeden'), findsOneWidget);
    expect(find.text('No notes yet.'), findsNothing);
    // Newest session first.
    expect(find.textContaining('p. null-null'), findsOneWidget);
    expect(find.textContaining('? pages, ? min - needs-quiz'), findsOneWidget);
    expect(find.textContaining('20 pages, 25 min - credited'), findsOneWidget);
  });

  testWidgets('a book with nothing yet says so for each part', (tester) async {
    await pump(tester, books.last);
    expect(
      find.text('p. 0/? - 0 pages credited - not started'),
      findsOneWidget,
    );
    expect(find.text('No notes yet.'), findsOneWidget);
    expect(find.text('No contents list.'), findsOneWidget);
    expect(find.text('No sessions yet.'), findsOneWidget);
    expect(find.text('Next Book'), findsOneWidget);
  });

  testWidgets('a finished book shows when it was finished', (tester) async {
    await pump(tester, books[1]);
    expect(
      find.text('p. 200/200 - 0 pages credited - finished 20.9.2026'),
      findsOneWidget,
    );
  });

  testWidgets("the newest session's summary and grader, earlier attempts", (
    tester,
  ) async {
    share.files['Reading/thumbs/p.jpg'] = tinyPng;
    await pump(tester, books.first);
    await expand(tester, '20 pages, 25 min');
    expect(find.text('second try'), findsOneWidget);
    expect(find.text('Grader'), findsOneWidget);
    expect(find.text('good'), findsOneWidget);
    expect(find.text('check p. 12'), findsOneWidget);
    expect(find.text('start p. ?'), findsOneWidget);
    await expand(tester, 'Attempt 1 - failed');
    expect(find.text('first try'), findsOneWidget);
    expect(find.text('mention the habit loop'), findsOneWidget);
  });

  testWidgets('a grader that is named shows next to its feedback', (
    tester,
  ) async {
    final json = libraryJson();
    final session = ((json['books'] as List).first as Map)['sessions'] as List;
    ((session.first as Map)['attempts'] as List).removeAt(1);
    await pump(tester, Library.fromJson(json).books.first);
    await expand(tester, '20 pages, 25 min');
    expect(find.text('Grader (claude:haiku)'), findsOneWidget);
    expect(find.textContaining('Attempt'), findsNothing);
  });

  testWidgets('a session without a summary says so', (tester) async {
    await pump(tester, books.first);
    await expand(tester, 'needs-quiz');
    expect(find.text('No summary written yet.'), findsOneWidget);
  });

  testWidgets('tapping a session photo opens it full size', (tester) async {
    share.files['Reading/thumbs/p.jpg'] = tinyPng;
    share.files['Reading/processed/p.jpg'] = tinyPng;
    await pump(tester, books.first);
    await expand(tester, '20 pages, 25 min');
    await tester.tap(find.text('check p. 12'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('a new note is kept on the device and queued for the PC', (
    tester,
  ) async {
    await pump(tester, books.first);
    await tester.tap(find.byTooltip('Add a note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Note'), 'mine');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Note saved on the device.'), findsOneWidget);
    expect(find.text('mine'), findsOneWidget);
    final sent = share.files.entries.singleWhere(
      (e) => e.key.startsWith('Reading/requests/'),
    );
    final request = jsonDecode(utf8.decode(sent.value)) as Map<String, dynamic>;
    expect(request['type'], 'note');
    expect(request['text'], 'mine');
  });

  testWidgets('editing a note replaces its text, a cancelled one nothing', (
    tester,
  ) async {
    await pump(tester, books.first);
    await tester.tap(find.text('from the PC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Note saved on the device.'), findsNothing);
    expect(share.files.keys.where((k) => k.contains('requests')), isEmpty);
    await tester.tap(find.text('from the PC'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'from the PC'),
      'edited',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('edited'), findsOneWidget);
    expect(find.text('from the PC'), findsNothing);
  });

  testWidgets('a note only on the phone is marked queued until the PC has it', (
    tester,
  ) async {
    await pump(tester, books.first);
    expect(find.textContaining('Queued: not on the PC yet'), findsNothing);
    await tester.tap(find.byTooltip('Add a note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Note'), 'mine');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Queued: not on the PC yet'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    // The PC stores it and lists it in library.json: the marker goes,
    // even on a screen opened from the older copy.
    final mine = (await api.deviceNotes()).single;
    final json = libraryJson();
    final book = (json['books'] as List).first as Map<String, dynamic>;
    book['notes'] = [...book['notes'] as List, mine.toJson()];
    putLibrary(share, json);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, books.first);
    expect(find.text('mine'), findsOneWidget);
    expect(find.textContaining('Queued: not on the PC yet'), findsNothing);
  });

  testWidgets('leaving before the notes load is harmless', (tester) async {
    await pump(tester, books.first);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
