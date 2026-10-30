import 'package:book_guard_app/src/ebook_paragraphs.dart';
import 'package:flutter_test/flutter_test.dart';

const _book =
    'TITLE OF THE BOOK\n\n'
    'First paragraph of the story.\n\n'
    '* * *\n\n'
    'After the break.\n\n'
    '— A short line of dialogue.\n\n'
    'ROZDZIAŁ II\n\n'
    'Chapter opening line.\n\n'
    'Second paragraph\nwith a line break inside.\n\n\n'
    '  Indented in the source.  \n\n';

void main() {
  final paragraphs = BookParagraphs.split(_book);
  List<String> texts() => [
    for (final p in paragraphs.all) _book.substring(p.start, p.end),
  ];

  test('paragraphs are exact slices of the text, trimmed', () {
    expect(texts(), [
      'TITLE OF THE BOOK',
      'First paragraph of the story.',
      '* * *',
      'After the break.',
      '— A short line of dialogue.',
      'ROZDZIAŁ II',
      'Chapter opening line.',
      'Second paragraph\nwith a line break inside.',
      'Indented in the source.',
    ]);
  });

  test('headings and scene breaks are told apart from short lines', () {
    expect(
      [for (final p in paragraphs.all) p.kind],
      [
        ParagraphKind.heading,
        ParagraphKind.text,
        ParagraphKind.sceneBreak,
        ParagraphKind.text,
        ParagraphKind.text,
        ParagraphKind.heading,
        ParagraphKind.text,
        ParagraphKind.text,
        ParagraphKind.text,
      ],
    );
  });

  test('no indent at the start or after a heading or a break', () {
    expect(
      [for (final p in paragraphs.all) p.indented],
      [
        false, // the book's first paragraph
        false, // after a heading
        false, // the break itself
        false, // after a break
        true, // dialogue is a normal paragraph
        false,
        false,
        true,
        true,
      ],
    );
  });

  test('every offset finds the paragraph it is in or follows', () {
    expect(paragraphs.indexOf(0), 0);
    expect(paragraphs.indexOf(-5), 0);
    final second = paragraphs.all[1];
    expect(paragraphs.indexOf(second.start), 1);
    expect(paragraphs.indexOf(second.end - 1), 1);
    expect(paragraphs.indexOf(second.end + 1), 1); // the gap after it
    expect(paragraphs.indexOf(_book.length + 9), paragraphs.length - 1);
  });

  test('a text with single line breaks only splits on them', () {
    const plain = 'One line.\nTwo line.\nThree.';
    final split = BookParagraphs.split(plain);
    expect(
      [for (final p in split.all) plain.substring(p.start, p.end)],
      ['One line.', 'Two line.', 'Three.'],
    );
  });

  test('an empty text has no paragraphs', () {
    expect(BookParagraphs.split('').length, 0);
    expect(BookParagraphs.split(' \n\n ').length, 0);
  });
}
