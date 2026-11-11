import 'package:book_guard_app/src/book_extras.dart';
import 'package:book_guard_app/src/journal.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pencil suggestion rides on the journal entry and the PC's photo
/// entry; it is never the page.
void main() {
  test('a journal entry keeps the phone pencil suggestion', () {
    final entry = JournalEntry(
      name: 'start_a.jpg',
      label: 'start',
      sha: 'f' * 64,
      takenAt: DateTime.utc(2026, 10, 3, 12, 27),
      pencilPage: 612,
    );
    expect(entry.page, isNull);
    final again = JournalEntry.fromJson(entry.toJson());
    expect(again.pencilPage, 612);
    expect(again.page, isNull);
    expect(entry.asSeen().pencilPage, 612);
  });

  test('an old journal row has no suggestion', () {
    final entry = JournalEntry.fromJson({
      'name': 'a.jpg',
      'label': 'start',
      'sha': 'f' * 64,
      'taken_at': '2026-10-03T12:27:00Z',
    });
    expect(entry.pencilPage, isNull);
    expect(entry.toJson().containsKey('pencil_page'), isFalse);
  });

  test('the PC photo entry carries its pencil suggestion', () {
    final info = PhotoInfo.fromJson({
      'name': 'a.jpg',
      'kind': 'other',
      'page': null,
      'status': 'rejected',
      'pencil_page': 29,
    });
    expect(info.page, isNull);
    expect(info.accepted, isFalse);
    expect(info.pencilPage, 29);
    expect(PhotoInfo.fromJson(const {}).pencilPage, isNull);
  });
}
