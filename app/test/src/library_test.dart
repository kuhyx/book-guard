import 'package:book_guard_app/src/library.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/library_json.dart';

void main() {
  test('parses books, sessions, attempts, photos and notes', () {
    final library = Library.fromJson(libraryJson());
    expect(library.books.map((b) => b.title), [
      'Atomic Habits',
      'Done Book',
      'Next Book',
    ]);
    final book = library.books.first;
    expect(book.pages, 320);
    expect(book.current, isTrue);
    expect(book.chapters, [
      (start: 9, title: 'Wstep'),
      (start: 25, title: 'Jeden'),
    ]);
    expect(book.firstReadAt, DateTime.utc(2026, 10, 2, 18));
    expect(book.pagesRead, 80);
    expect(book.lastPageRead, 81);
    expect(book.sessions.length, 2);
    final session = book.sessions.first;
    expect(session.startPage, 1);
    expect(session.minutes, 25);
    expect(session.attempts.first, (
      passed: false,
      summary: 'first try',
      feedback: 'mention the habit loop',
      grader: 'claude:haiku',
    ));
    expect(session.attempts.last.grader, '');
    expect(session.photos.first.page, 12);
    expect(session.photos.last.page, isNull);
    expect(book.notes.single.text, 'from the PC');
  });

  test('a book with only the basics gets safe defaults', () {
    final book = Library.fromJson(libraryJson()).books.last;
    expect(book.author, '');
    expect(book.pages, isNull);
    expect(book.current, isFalse);
    expect(book.chapters, isEmpty);
    expect(book.finishedAt, isNull);
    expect(book.pagesRead, 0);
    expect(book.sessions, isEmpty);
    expect(book.notes, isEmpty);
    final session = LibrarySession.fromJson(const {});
    expect(session.id, '');
    expect(session.attempts, isEmpty);
    expect(Library.fromJson(const {}).books, isEmpty);
  });

  test('a note round-trips through its JSON', () {
    final note = Note(
      id: 'n1',
      isbn: '9',
      text: 'hello',
      page: 4,
      chapter: 'One',
      createdAt: DateTime.utc(2026, 10, 3, 10),
      updatedAt: DateTime.utc(2026, 10, 3, 11),
    );
    final back = Note.fromJson(note.toJson());
    expect(back.toJson(), note.toJson());
    expect(note.toJson()['updated_at'], '2026-10-03T11:00:00.000Z');
    final bare = Note.fromJson(const {});
    expect(bare.text, '');
    expect(bare.page, isNull);
    expect(bare.createdAt, DateTime(2000));
  });
}
