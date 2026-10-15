import 'package:book_guard_app/src/book_formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("the groups are the PC's, in modal order", () {
    expect(bookFormatGroups.map((g) => g.key), [
      'calibre',
      'pdf',
      'djvu',
      'text',
    ]);
    expect(
      bookExtensions.length,
      bookFormatGroups.fold(0, (n, g) => n + g.extensions.length),
    );
    expect(bookExtensions.toSet().length, bookExtensions.length);
    expect(bookExtensions, containsAll(['epub', 'pdf', 'djv', 'xhtml']));
  });

  test('isBookFile goes by the extension, any case', () {
    expect(isBookFile('Atomic.epub'), isTrue);
    expect(isBookFile('SCAN.PDF'), isTrue);
    expect(isBookFile('a.b.djvu'), isTrue);
    expect(isBookFile('.epub'), isTrue);
    expect(isBookFile('movie.mkv'), isFalse);
    expect(isBookFile('epub'), isFalse);
    expect(isBookFile('trailing.'), isFalse);
    expect(isBookFile(''), isFalse);
  });
}
