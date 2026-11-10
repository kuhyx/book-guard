import 'package:book_guard_app/src/library.dart';
import 'package:book_guard_app/src/screens/note_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_book.dart';

LibraryBook _book({bool chapters = true}) => LibraryBook(
  isbn: '978',
  title: 'T',
  author: '',
  status: 'reading',
  chapters: chapters
      ? const [(start: 1, title: 'One'), (start: 9, title: 'Two')]
      : const [],
);

final _old = Note(
  id: 'keep',
  isbn: '978',
  text: 'old text',
  page: 4,
  chapter: 'Gone',
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10),
);

void main() {
  late Note? result;
  late int ids;

  Future<void> open(
    WidgetTester tester, {
    LibraryBook? book,
    Note? existing,
  }) async {
    result = null;
    ids = 0;
    await pumpTab(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await editNote(
            context,
            book: book ?? _book(),
            newId: () => 'new${++ids}',
            existing: existing,
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a new note gets a fresh id, its page and chapter', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await typeInto(tester, 'Note', '  hello  ');
    await typeInto(tester, 'Page (optional)', ' 12 ');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Two'));
    await tester.pumpAndSettle();
    await tester.tap(iconLabeled('Save'));
    await tester.pumpAndSettle();
    expect(result!.id, 'new1');
    expect(result!.isbn, '978');
    expect(result!.text, 'hello');
    expect(result!.page, 12);
    expect(result!.chapter, 'Two');
    expect(result!.createdAt, result!.updatedAt);
  });

  testWidgets('an empty note is never saved', (tester) async {
    await open(tester);
    await typeInto(tester, 'Note', '   ');
    await tester.tap(iconLabeled('Save'));
    await tester.pumpAndSettle();
    // Still open, and the note field is red until something is typed.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fieldIsRed(tester, 'Note'), isTrue);
    expect(result, isNull);
    expect(ids, 0);
    await typeInto(tester, 'Note', 'x');
    expect(fieldIsRed(tester, 'Note'), isFalse);
  });

  testWidgets('cancel returns nothing', (tester) async {
    await open(tester);
    await tester.tap(iconLabeled('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, isNull);
  });

  testWidgets('editing keeps the id and birth, and the odd chapter', (
    tester,
  ) async {
    await open(tester, existing: _old);
    expect(find.text('old text'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    // The chapter the book no longer lists stays, chosen.
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Gone'))
          .selected,
      isTrue,
    );
    await typeInto(tester, 'Note', 'new');
    await typeInto(tester, 'Page (optional)', 'x');
    await tester.tap(iconLabeled('Save'));
    await tester.pumpAndSettle();
    expect(result!.id, 'keep');
    expect(result!.createdAt, _old.createdAt);
    expect(result!.updatedAt.isAfter(_old.updatedAt), isTrue);
    expect(result!.text, 'new');
    expect(result!.page, isNull);
    expect(result!.chapter, 'Gone');
    expect(ids, 0);
  });

  testWidgets('a book without contents has no chapter chips', (tester) async {
    await open(tester, book: _book(chapters: false));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(iconLabeled('Chapter'), findsNothing);
  });

  testWidgets('tapping the chosen chapter again clears it', (tester) async {
    await open(tester, existing: _old);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Gone'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is ChoiceChip && w.selected),
      findsNothing,
    );
    await tester.tap(iconLabeled('Save'));
    await tester.pumpAndSettle();
    expect(result!.chapter, '');
  });
}
