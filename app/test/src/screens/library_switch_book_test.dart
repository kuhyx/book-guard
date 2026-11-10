import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/iso_offset.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:book_guard_app/src/ui/hold_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_book.dart';
import '../../support/library_api.dart';
import '../../support/library_json.dart';
import '../../support/states.dart';

void main() {
  late FakeApi api;
  late List<LibraryBook> books;
  String? switched;

  setUp(() {
    api = FakeApi()..offline = true;
    books = Library.fromJson(libraryJson()).books;
    switched = null;
  });

  Future<void> pump(
    WidgetTester tester,
    LibraryBook book, {
    GuardState? state,
  }) async {
    tallSurface(tester);
    await pumpTab(
      tester,
      LibraryBookScreen(
        api: api,
        book: book,
        state: state,
        onSwitched: (isbn) => switched = isbn,
      ),
    );
    await settle(tester);
  }

  final readNow = iconLabeled('Read this now');
  final warning = iconLabeled('A session is open: take its stop photo first');

  testWidgets('the current book has no button', (tester) async {
    await pump(tester, books.first);
    expect(readNow, findsNothing);
  });

  testWidgets('another book queues switch_book with an offset-aware time', (
    tester,
  ) async {
    await pump(tester, books[1]);
    final before = DateTime.now();
    await tester.tap(readNow);
    await settle(tester);
    final sent = api.sent.single;
    expect(sent.type, 'switch_book');
    expect(sent.body['isbn'], books[1].isbn);
    final at = '${sent.body['at']}';
    expect(at, matches(RegExp(r'T\d\d:\d\d:\d\d[+-]\d\d:\d\d$')));
    final parsed = DateTime.parse(at);
    expect(parsed.difference(before).inSeconds.abs(), lessThan(5));
    expect(switched, books[1].isbn);
    expect(readNow, findsNothing);
  });

  testWidgets('an open paper session asks first; cancel queues nothing', (
    tester,
  ) async {
    await pump(tester, books[1], state: readingState(openStart: 12));
    await tester.tap(readNow);
    await settle(tester);
    expect(warning, findsOneWidget);
    await tester.tap(iconLabeled('Cancel'));
    await settle(tester);
    expect(api.sent, isEmpty);
    expect(switched, isNull);
    expect(readNow, findsOneWidget);
    await tester.tap(readNow);
    await settle(tester);
    // A plain tap on the ring does nothing: it must be held until it fills.
    await tester.tap(find.byType(HoldButton));
    await settle(tester);
    expect(api.sent, isEmpty);
    await holdFor(tester, find.byType(HoldButton));
    await settle(tester);
    expect(api.sent.single.type, 'switch_book');
    expect(switched, books[1].isbn);
  });

  testWidgets('a running in-app session asks first too', (tester) async {
    await api.startReading(
      ReadingStart(
        id: 'r1',
        isbn: books.first.isbn,
        offset: 0,
        startedAt: DateTime(2026, 11, 8, 9),
        textSha: 'x',
      ),
    );
    await api.store.write(
      'library.json',
      Uint8List.fromList(utf8.encode(jsonEncode(libraryJson()))),
    );
    await pump(tester, books[1], state: readingState());
    await tester.tap(readNow);
    await settle(tester);
    expect(warning, findsOneWidget);
    await tester.tap(iconLabeled('Cancel'));
    await settle(tester);
    expect(api.sent, isEmpty);
  });

  testWidgets('letting go of the ring early switches nothing', (tester) async {
    await pump(tester, books[1], state: readingState(openStart: 12));
    await tester.tap(readNow);
    await settle(tester);
    await holdFor(
      tester,
      find.byType(HoldButton),
      const Duration(milliseconds: 300),
    );
    await settle(tester);
    expect(api.sent, isEmpty);
    expect(switched, isNull);
    expect(warning, findsOneWidget);
  });

  testWidgets('a refusal is shown and the book stays switchable', (
    tester,
  ) async {
    api
      ..offline = false
      ..onSend = (r) async =>
          const GuardResponse(ok: false, code: 'unknown_book');
    await pump(tester, books[1]);
    await tester.tap(readNow);
    await settle(tester);
    expect(cueGlyph(Icons.search_off), findsOneWidget);
    expect(cueOf(CueKind.error), findsOneWidget);
    expect(switched, isNull);
    expect(readNow, findsOneWidget);
  });

  test('isoWithOffset writes the wall clock and the UTC offset', () {
    final text = isoWithOffset(DateTime(2026, 11, 8, 9, 30, 5));
    expect(text, startsWith('2026-11-08T09:30:05'));
    expect(text, matches(RegExp(r'[+-]\d\d:\d\d$')));
    final utc = DateTime.utc(2026, 11, 8, 9);
    expect(DateTime.parse(isoWithOffset(utc)).isAtSameMomentAs(utc), isTrue);
  });
}
