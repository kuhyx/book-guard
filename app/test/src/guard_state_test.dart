import 'package:book_guard_app/src/guard_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/states.dart';

void main() {
  test('parses a full snapshot', () {
    final state = GuardState.fromJson(fullState());
    expect(state.locked, isTrue);
    expect(state.reason, 'Read 20 pages to unlock');
    expect(state.book?.title, 'Atomic Habits');
    expect(state.book?.author, 'James Clear');
    expect(state.book?.isbn, '9780735211292');
    expect(state.book?.pages, 320);
    expect(state.book?.hasFile, isTrue);
    final pace = state.pace;
    expect(
      [pace.month, pace.target, pace.pages, pace.required, pace.behind],
      ['2026-09', 320, 120, 250, 130],
    );
    expect(pace.carriedDebt, 20);
    expect(state.todo, ['Photograph page 42', '7']);
    expect(state.sessions, hasLength(3));
    expect(state.openStart, 55);
    expect(state.generatedAt, DateTime.utc(2026, 9, 26, 10, 30));
  });

  test('parses sessions and splits them by what they wait for', () {
    final state = GuardState.fromJson(fullState());
    final first = state.sessions.first;
    expect(first.id, 'session:a-b');
    expect([first.startPage, first.endPage, first.checkPage], [1, 20, 12]);
    expect([first.pages, first.minutes], [20, 30]);
    expect(first.startedAt, DateTime.utc(2026, 9, 26, 10));
    expect(state.needCheck.single.id, 'session:a-b');
    expect(state.needSummary.single.id, 'session:c-d');
    expect(state.needSummary.single.startPage, 21);
    final bare = state.sessions.last;
    expect([bare.id, bare.endPage, bare.pages, bare.minutes], ['', 0, 0, 0]);
    expect(bare.checkPage, isNull);
    expect(bare.startedAt, isNull);
  });

  test('an empty document gives safe defaults', () {
    final state = GuardState.fromJson(const {});
    expect(state.locked, isFalse);
    expect(state.reason, '');
    expect(state.book, isNull);
    expect(state.pace.month, '');
    expect(state.pace.target, 0);
    expect(state.pace.carriedDebt, 0);
    expect(state.todo, isEmpty);
    expect(state.sessions, isEmpty);
    expect(state.openStart, isNull);
    expect(state.generatedAt, isNull);
    expect(state.needCheck, isEmpty);
  });

  test('wrong shapes are ignored rather than thrown', () {
    final state = GuardState.fromJson({
      'book': 'none',
      'open_start': 12,
      'pace': {'target': 'many'},
    });
    expect(state.book, isNull);
    expect(state.openStart, isNull);
    expect(state.pace.target, 0);
  });

  test('a book with nothing filled in', () {
    final book = BookInfo.fromJson(const {});
    expect([book.isbn, book.title, book.author], ['', '', '']);
    expect(book.pages, isNull);
    expect(book.hasFile, isFalse);
  });
}
