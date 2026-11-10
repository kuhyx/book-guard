import 'dart:convert';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:book_guard_app/src/screens/library_session_tile.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/fake_share.dart';
import '../../support/finders_book.dart';
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

  /// Opens the session tile whose date is [date] (`02.10.2026`).
  Future<void> expand(WidgetTester tester, String date) async {
    await tester.tap(find.text(date));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the book, its notes, chapters and sessions', (
    tester,
  ) async {
    await pump(tester, books.first);
    expect(find.text('James Clear'), findsOneWidget);
    expect(find.text('81/320'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(tester.widget<Icon>(iconLabeled('reading')).icon, Icons.timelapse);
    expect(find.text('from the PC'), findsOneWidget);
    expect(find.text('03.10.2026'), findsOneWidget);
    expect(glyphNumber(find.byType(ListTile).first, '12'), findsOneWidget);
    expect(find.text('Jeden'), findsWidgets);
    expect(find.text('Wstep'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(iconLabeled('Notes'), findsOneWidget);
    expect(iconLabeled('Chapters'), findsOneWidget);
    expect(iconLabeled('Sessions'), findsOneWidget);
    // The chapter's start page and the session's minutes.
    expect(find.text('25'), findsNWidgets(2));
    // Newest session first: the unfinished one, then the credited one.
    final tiles = tester.widgetList<ExpansionTile>(find.byType(ExpansionTile));
    expect(tiles, hasLength(2));
    expect(find.text('20'), findsOneWidget);
    expect(find.text('1-20'), findsOneWidget);
    expect(find.text('?-?'), findsOneWidget);
    expect(
      tester.widget<Icon>(iconLabeled('credited')).icon,
      Icons.check_circle,
    );
    expect(
      tester.widget<Icon>(iconLabeled('write the summary')).icon,
      Icons.edit,
    );
  });

  testWidgets('a book with nothing yet is an outline for each part', (
    tester,
  ) async {
    await pump(tester, books.last);
    expect(find.text('0/?'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(
      tester.widget<Icon>(iconLabeled('not-started')).icon,
      Icons.hourglass_empty,
    );
    for (final part in ['Notes', 'Chapters', 'Sessions']) {
      expect(tester.widget<Icon>(iconLabeled(part)).size, 64);
    }
    expect(find.text('Next Book'), findsOneWidget);
  });

  testWidgets('a finished book shows when it was finished', (tester) async {
    await pump(tester, books[1]);
    expect(find.text('200/200'), findsOneWidget);
    expect(
      tester.widget<Icon>(iconLabeled('finished')).icon,
      Icons.check_circle,
    );
    expect(find.text('20.09.2026'), findsOneWidget);
  });

  testWidgets("the newest session's summary and grader, earlier attempts", (
    tester,
  ) async {
    share.files['Reading/thumbs/p.jpg'] = tinyPng;
    await pump(tester, books.first);
    await expand(tester, '02.10.2026');
    expect(find.text('second try'), findsOneWidget);
    expect(find.text('good'), findsOneWidget);
    expect(iconLabeled('Grader'), findsOneWidget);
    expect(glyphNumber(find.byType(InkWell), '12'), findsWidgets);
    expect(iconLabeled('check'), findsOneWidget);
    expect(iconLabeled('start'), findsOneWidget);
    expect(find.text('?'), findsWidgets);
    // The earlier attempt: a red cross and its number.
    final failed = tester.widget<Icon>(iconLabeled('Failed'));
    expect(failed.icon, Icons.cancel);
    await tester.tap(iconLabeled('Failed'));
    await tester.pumpAndSettle();
    expect(find.text('first try'), findsOneWidget);
    expect(find.text('mention the habit loop'), findsOneWidget);
  });

  testWidgets('a grader that is named shows as its glyph by the feedback', (
    tester,
  ) async {
    final json = libraryJson();
    final session = ((json['books'] as List).first as Map)['sessions'] as List;
    ((session.first as Map)['attempts'] as List).removeAt(1);
    await pump(tester, Library.fromJson(json).books.first);
    await expand(tester, '02.10.2026');
    final icon = tester.widget<Icon>(iconLabeled('claude:haiku'));
    expect(icon.icon, graderIcon('claude:haiku'));
    expect(icon.icon, Icons.cloud);
    expect(graderIcon('local:qwen3:32b'), Icons.computer);
    expect(iconLabeled('Failed'), findsNothing);
    expect(iconLabeled('Passed'), findsNothing);
  });

  testWidgets('a session without a summary is an outline, not a sentence', (
    tester,
  ) async {
    await pump(tester, books.first);
    // The unfinished session has no end date: its date shows as a dash.
    await expand(tester, '-');
    expect(tester.widget<Icon>(iconLabeled('No summary yet')).size, 64);
  });

  testWidgets('tapping a session photo opens it full size', (tester) async {
    share.files['Reading/thumbs/p.jpg'] = tinyPng;
    share.files['Reading/processed/p.jpg'] = tinyPng;
    await pump(tester, books.first);
    await expand(tester, '02.10.2026');
    await tester.tap(iconLabeled('check'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('a new note is kept on the device and queued for the PC', (
    tester,
  ) async {
    await pump(tester, books.first);
    await tester.tap(iconLabeled('Add a note'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Note', 'mine');
    await tester.tap(iconLabeled('Save'));
    await tester.pumpAndSettle();
    expect(cueGlyph(Icons.check_circle), findsOneWidget);
    expect(cueOf(CueKind.ok), findsOneWidget);
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
    await tester.tap(iconLabeled('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(StatusCue), findsNothing);
    expect(share.files.keys.where((k) => k.contains('requests')), isEmpty);
    await tester.tap(find.text('from the PC'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Note', 'edited');
    await tester.tap(iconLabeled('Save'));
    await tester.pumpAndSettle();
    expect(find.text('edited'), findsOneWidget);
    expect(find.text('from the PC'), findsNothing);
  });

  testWidgets('a note only on the phone is marked queued until the PC has it', (
    tester,
  ) async {
    await pump(tester, books.first);
    final queued = iconLabeled('Queued: not on the PC yet');
    expect(queued, findsNothing);
    await tester.tap(iconLabeled('Add a note'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Note', 'mine');
    await tester.tap(iconLabeled('Save'));
    await tester.pumpAndSettle();
    expect(queued, findsOneWidget);
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
    expect(queued, findsNothing);
  });

  testWidgets('leaving before the notes load is harmless', (tester) async {
    await pump(tester, books.first);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
