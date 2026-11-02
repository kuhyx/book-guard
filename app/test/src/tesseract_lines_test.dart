import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/tesseract_lines.dart';
import 'package:flutter_test/flutter_test.dart';

Map<Object?, Object?> _word(String text, int l, int t, int r, int b, num c) => {
  'text': text,
  'left': l,
  'top': t,
  'right': r,
  'bottom': b,
  'conf': c,
};

void main() {
  test('words become a line: joined text, union box, per-word data', () {
    final lines = linesFromChannel([
      [_word('Page', 10, 20, 50, 40, 0.9), _word('19', 60, 22, 80, 44, 1)],
      <Object?>[],
    ]);
    expect(lines, hasLength(1));
    final line = lines.single;
    expect(line.text, 'Page 19');
    expect(line.box, (left: 10, top: 20, right: 80, bottom: 44));
    expect(line.words, [
      ('Page', (left: 10, top: 20, right: 50, bottom: 40)),
      ('19', (left: 60, top: 22, right: 80, bottom: 44)),
    ]);
    expect(line.confidence, [0.9, 1.0]);
    expect(line.angle, isNull);
  });

  test('nothing back means no lines', () {
    expect(linesFromChannel(null), isEmpty);
    expect(linesFromChannel(<Object?>[]), isEmpty);
  });

  test('unsure words are left out; a line with none left is dropped', () {
    final raw = [
      [_word('7', 1, 1, 9, 9, 0.5)],
      [_word('9', 1, 1, 9, 9, 0.8), _word('=D', 12, 1, 20, 9, 0.2)],
    ];
    expect(linesFromChannel(raw), hasLength(2));
    final sure = linesFromChannel(raw, minConfidence: 0.6);
    expect(sure.map((l) => l.text), ['9']);
    expect(sure.single.box, (left: 1, top: 1, right: 9, bottom: 9));
  });

  test('only the sure words of a line count for the turn score', () {
    final lines = linesFromChannel([
      [
        _word('Hello', 0, 0, 50, 10, 0.9),
        _word('garbage', 60, 0, 120, 10, 0.3),
      ],
    ]);
    final sure = sureWords(lines);
    expect(sure.single.words.map((w) => w.$1), ['Hello']);
    expect(sure.single.text, 'Hello garbage');
  });

  test('a window line is moved onto the page and scaled', () {
    const line = SeenLine(
      '7',
      (left: 10, top: 20, right: 30, bottom: 40),
      words: [('7', (left: 10, top: 20, right: 30, bottom: 40))],
      confidence: [0.9],
    );
    final placed = placeLine(line, 100, 1000, 0.5);
    expect(placed.box, (left: 55, top: 510, right: 65, bottom: 520));
    expect(placed.words.single.$2, placed.box);
    expect(placed.confidence, [0.9]);
  });

  test('overlapping windows reading one number leave one line', () {
    SeenLine at(String text, int x) =>
        SeenLine(text, (left: x, top: 5, right: x + 20, bottom: 25));
    final kept = withoutRepeats([at('7', 100), at('7', 105), at('8', 100)]);
    expect(kept.map((l) => l.text), ['7', '8']);
    final far = withoutRepeats([at('7', 100), at('7', 900)]);
    expect(far, hasLength(2));
    final higher = withoutRepeats([
      at('7', 100),
      const SeenLine('7', (left: 100, top: 500, right: 120, bottom: 520)),
    ]);
    expect(higher, hasLength(2));
  });
}
