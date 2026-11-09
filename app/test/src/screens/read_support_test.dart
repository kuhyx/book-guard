import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/read_support.dart';
import 'package:flutter_test/flutter_test.dart';

const _crime = '9788368380002';
const _fantasy = '9788368380019';

GuardState _state({int? latest}) => GuardState.fromJson({
  'book': {
    'isbn': _crime,
    'title': 'Zbrodnia i kara',
    'pages': 611,
    'latest_page': ?latest,
  },
  // The snapshot's sessions carry no book: they span every book.
  'sessions': [
    {
      'id': 'session:other',
      'start_page': 100,
      'end_page': 130,
      'status': 'credited',
      'started_at': '2026-11-07T19:00:00Z',
    },
  ],
});

JournalEntry _stop(int page, String? isbn, {bool seen = false}) => JournalEntry(
  name: 'stop_$page.jpg',
  label: 'stop',
  sha: 'a' * 64,
  takenAt: DateTime.utc(2026, 11, 7, 20),
  page: page,
  isbn: isbn,
  seen: seen,
);

void main() {
  test("another book's stop or session is not where this one ended", () {
    // 2026-11-08: first start after switching books; the phone read 502 and
    // judged it far from the other book's p. 130.
    final context = pageContextFor('start', _state(), [
      _stop(130, _fantasy),
    ], null);
    expect(context.near, isNull);
    expect(context.lastPage, 611);
  });

  test("the PC's per-book latest page is where a start must be near", () {
    final context = pageContextFor('start', _state(latest: 502), [
      _stop(130, _fantasy, seen: true),
    ], null);
    expect(context.near, 502);
  });

  test("this book's stop the PC has not read yet is the newest", () {
    final context = pageContextFor('start', _state(latest: 20), [
      _stop(51, _crime),
    ], null);
    expect(context.near, 51);
    expect(
      pageContextFor('start', _state(latest: 20), [
        _stop(51, _crime, seen: true),
      ], null).near,
      20,
    );
  });

  test('a read stop of this book stands in when the PC names none', () {
    final context = pageContextFor('start', _state(), [
      _stop(51, _crime, seen: true),
      _stop(130, _fantasy),
    ], null);
    expect(context.near, 51);
  });

  test('with no book known, the newest stop or session is used', () {
    expect(pageContextFor('start', null, [_stop(51, null)], null).near, 51);
    final state = GuardState.fromJson({
      'sessions': [
        {'id': 's', 'start_page': 1, 'end_page': 9, 'status': 'credited'},
      ],
    });
    expect(pageContextFor('start', state, const [], null).near, 9);
  });

  test('check and stop photos keep their own anchors', () {
    final check = pageContextFor('check19', _state(), const [], null);
    expect((check.expected, check.lastPage), (19, 611));
    final stop = pageContextFor('stop', _state(), const [], 556);
    expect((stop.after, stop.lastPage), (556, 611));
  });
}
