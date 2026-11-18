import 'package:book_guard_app/src/ebook_map.dart';
import 'package:book_guard_app/src/ebook_models.dart';
import 'package:book_guard_app/src/screens/ebook_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reader's exit uses the PC's speed floor (`MIN_SECONDS_PER_PAGE`).
void main() {
  // 1000 characters a page: offset 60000 is 60 pages on.
  const map = EbookMap(
    knots: [(offset: 0, page: 1), (offset: 600000, page: 601)],
    start: 0,
    end: 600000,
    lastPage: 601,
    photos: 0,
  );
  final t0 = DateTime(2026, 11, 18, 20, 10, 47);
  final start = ReadingStart(
    id: 'r',
    isbn: 'x',
    offset: 0,
    startedAt: t0,
    textSha: '',
  );

  test('the floor is 38 s a page', () => expect(minSecondsPerPage, 38));

  test('60 pages in 2290 s count, in 2279 s are too fast', () {
    ReaderExit at(int seconds) =>
        judgeExit(start, 60000, map, t0.add(Duration(seconds: seconds)));
    expect(at(2290), ReaderExit.stop);
    expect(at(2279), ReaderExit.tooFast);
  });
}
