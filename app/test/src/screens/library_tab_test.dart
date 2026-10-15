import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:book_guard_app/src/screens/library_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/fake_share.dart';
import '../../support/library_api.dart';
import '../../support/library_json.dart';
import '../../support/states.dart';

void main() {
  late FakeShare share;

  setUp(() => share = FakeShare());

  test('dmy is day.month.year, or a dash', () {
    expect(dmy(null), '-');
    expect(dmy(DateTime(2026, 10, 5, 12)), '5.10.2026');
  });

  testWidgets('a spinner until the first copy arrives', (tester) async {
    final hung = HungShare();
    await pumpTab(tester, LibraryTab(api: hung.api, state: null));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    hung.release();
    await settle(tester);
    expect(find.text('No books yet'), findsOneWidget);
  });

  testWidgets('lists every book with its dates and counts', (tester) async {
    tallSurface(tester);
    putLibrary(share, libraryJson());
    await pumpTab(tester, LibraryTab(api: libraryApi(share), state: null));
    await settle(tester);
    expect(find.text('Atomic Habits'), findsOneWidget);
    expect(
      find.text(
        'James Clear\np. 81/320 - 2.10.2026 - 14.10.2026\n'
        '2 sessions, 1 note',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('p. 200/200 - finished 20.9.2026'),
      findsOneWidget,
    );
    expect(find.textContaining('p. 0/? - not started'), findsOneWidget);
    expect(find.byIcon(Icons.auto_stories), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.book_outlined), findsOneWidget);
  });

  testWidgets('the kept copy shows at once, before the PC answers', (
    tester,
  ) async {
    putLibrary(share, libraryJson());
    final api = libraryApi(share);
    await api.loadLibrary();
    final hung = HungShare();
    // Same device storage, but a PC that never answers.
    final offline = hung.apiWith(api.store);
    await pumpTab(tester, LibraryTab(api: offline, state: null));
    await settle(tester);
    expect(find.text('Atomic Habits'), findsOneWidget);
    hung.release();
    await settle(tester);
  });

  testWidgets('with the PC down the kept copy still shows', (tester) async {
    putLibrary(share, libraryJson());
    final api = libraryApi(share);
    await api.loadLibrary();
    share.down = true;
    await pumpTab(tester, LibraryTab(api: api, state: null));
    await settle(tester);
    expect(find.text('Done Book'), findsOneWidget);
  });

  testWidgets('a newer snapshot reloads, so does a pull', (tester) async {
    putLibrary(share, {'books': <Object>[]});
    final api = libraryApi(share);
    Future<void> pump(String generatedAt) => pumpTab(
      tester,
      LibraryTab(api: api, state: sampleState({'generated_at': generatedAt})),
    );
    await pump('2026-10-15T10:00:00Z');
    await settle(tester);
    expect(find.text('No books yet'), findsOneWidget);
    putLibrary(share, libraryJson());
    await pump('2026-10-15T10:00:10Z');
    await settle(tester);
    expect(find.text('Atomic Habits'), findsOneWidget);
    putLibrary(share, {'books': <Object>[]});
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('No books yet'), findsOneWidget);
  });

  testWidgets('tapping a book opens its screen', (tester) async {
    tallSurface(tester);
    putLibrary(share, libraryJson());
    await pumpTab(tester, LibraryTab(api: libraryApi(share), state: null));
    await settle(tester);
    await tester.tap(find.text('Done Book'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryBookScreen), findsOneWidget);
  });

  test('counted pluralises', () {
    expect(counted(0, 'note'), '0 notes');
    expect(counted(1, 'note'), '1 note');
    expect(counted(2, 'session'), '2 sessions');
  });

  testWidgets('notes still only on the phone count too, also after a visit', (
    tester,
  ) async {
    tallSurface(tester);
    putLibrary(share, libraryJson());
    final api = libraryApi(share);
    final books = Library.fromJson(libraryJson()).books;
    final now = DateTime.utc(2026, 10, 15);
    Note note(String id, String isbn) =>
        Note(id: id, isbn: isbn, text: id, createdAt: now, updatedAt: now);
    await api.saveNote(note('phone', books.first.isbn));
    await pumpTab(tester, LibraryTab(api: api, state: null));
    await settle(tester);
    expect(find.textContaining('2 sessions, 2 notes'), findsOneWidget);
    await tester.tap(find.text('Done Book'));
    await tester.pumpAndSettle();
    await api.saveNote(note('later', books[1].isbn));
    await tester.pageBack();
    await settle(tester);
    expect(find.textContaining('1 note'), findsOneWidget);
  });

  testWidgets('closing the tab while loading is harmless', (tester) async {
    final hung = HungShare();
    await pumpTab(tester, LibraryTab(api: hung.api, state: null));
    await tester.pumpWidget(const SizedBox());
    hung.release();
    await settle(tester);
  });
}
