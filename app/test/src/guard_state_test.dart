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

  test('parses chapters, the current chapter, photos and session detail', () {
    final state = GuardState.fromJson({
      'book': {
        'title': 'Cesarz',
        'chapters': [
          {'start': 9, 'title': 'Wstęp'},
          'junk',
          {'start': '25', 'title': 'Rozdział 1'},
        ],
        'chapter': {'number': 2, 'of': 2, 'title': 'Rozdział 1'},
      },
      'photos': [
        {
          'name': 'check19_a.jpg',
          'file': 'processed/abc-check19_a.jpg',
          'thumb': 'thumbs/abc.jpg',
          'kind': 'page',
          'page': 19,
          'status': 'ok',
          'taken_at': '2026-10-02T18:14:00Z',
        },
        7,
        <String, dynamic>{},
      ],
      'sessions': [
        {'id': 's', 'detail': 'sessions/s.json'},
      ],
    });
    final book = state.book!;
    expect(
      [for (final c in book.chapters) (c.start, c.title)],
      [(9, 'Wstęp'), (25, 'Rozdział 1')],
    );
    expect(book.chapters.first.toJson(), {'start': 9, 'title': 'Wstęp'});
    expect(book.chapter?.label, 'Chapter 2 of 2: Rozdział 1');
    final photo = state.photos.first;
    expect(
      (photo.name, photo.file, photo.thumb, photo.page, photo.takenAt),
      (
        'check19_a.jpg',
        'processed/abc-check19_a.jpg',
        'thumbs/abc.jpg',
        19,
        DateTime.utc(2026, 10, 2, 18, 14),
      ),
    );
    expect(state.photos, hasLength(2));
    final bare = state.photos.last;
    expect((bare.kind, bare.page, bare.takenAt), ('', null, null));
    expect(state.sessions.single.detail, 'sessions/s.json');
  });

  test('a bare book has no chapters and no current chapter', () {
    final book = GuardState.fromJson({
      'book': {
        'title': 'T',
        'chapter': 'junk',
        'chapters': [
          {'title': 'no start'},
        ],
      },
    }).book!;
    expect(book.chapter, isNull);
    expect(book.chapters.single.start, 0);
    const empty = CurrentChapter(number: 0, of: 0, title: '');
    expect(CurrentChapter.fromJson(const {}).label, empty.label);
  });

  test('photo captions say what the PC made of each photo', () {
    PhotoInfo photo(String kind, {int? page, String status = 'ok'}) =>
        PhotoInfo.fromJson({
          'kind': kind,
          'page': page,
          'status': status,
          'reason': 'too late',
        });
    expect(photo('page', page: 7).caption, 'page 7');
    expect(photo('page').caption, 'page ?');
    expect(photo('isbn').caption, 'barcode');
    expect(photo('toc').caption, 'contents');
    expect(photo('other').caption, 'not a page');
    expect(
      photo('page', page: 1, status: 'rejected').caption,
      'page 1 - rejected: too late',
    );
    expect(photo('page', page: 7).accepted, isTrue);
    expect(photo('other').accepted, isFalse);
    expect(photo('page', page: 7, status: 'rejected').accepted, isFalse);
  });
}
