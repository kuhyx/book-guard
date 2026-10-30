import 'package:book_guard_app/src/page_number.dart';
import 'package:flutter_test/flutter_test.dart';

Box _b(int l, int t, int r, int b) => (left: l, top: t, right: r, bottom: b);

NumberHit _hit(int value) => NumberHit(value, _b(0, 0, 1, 1));

void main() {
  test('number lines are lone numbers in the top or bottom fifth', () {
    final lines = [
      SeenLine('3', _b(40, 10, 50, 20)),
      SeenLine(' 51 ', _b(40, 950, 50, 960)),
      SeenLine('12', _b(40, 500, 50, 510)),
      SeenLine('page 7', _b(40, 950, 80, 960)),
      SeenLine('12345', _b(40, 950, 80, 960)),
    ];
    expect(numberLines(lines, 1000).map((h) => h.$2.text), ['3', ' 51 ']);
  });

  test('ornaments either side of a page number do not hide it', () {
    // p. 9 of 2026-10-30: "9" centred between two swashes at the page foot.
    SeenLine line(List<(String, double?)> words) => SeenLine(
      words.map((w) => w.$1).join(' '),
      _b(40, 950, 80, 960),
      words: [for (final (t, _) in words) (t, _b(40, 950, 80, 960))],
      confidence: [for (final (_, c) in words) c],
    );
    final lines = [
      line([('z', 0.3), ('9', 0.95), ('s', 0.4)]), // swashes read as junk
      line([('~', null), ('9', null), ('~', null)]), // symbols, no confidence
      SeenLine('~9~', _b(40, 950, 80, 960)), // one glued element
      line([('s.', 0.9), ('18', 0.95)]), // a citation: real word beside it
      line([('C', 0.3), ('9', 0.4), ('s', 0.4)]), // the number itself unsure
    ];
    expect(lines.map(loneNumber), [9, 9, 9, null, null]);
    expect(numberLines(lines, 1000).map((h) => h.$1), [9, 9, 9]);
    // A bare number on the page wins: the relaxed rule is only a fallback.
    final bare = SeenLine('51', _b(40, 10, 50, 20));
    expect(numberLines([...lines, bare], 1000).map((h) => h.$1), [51]);
  });

  test('a boxed number read upside down is no reading', () {
    // A flipped "9" reads "6": a line ML Kit read turned from the page's
    // upright is not trusted, whatever digits it shows.
    expect(boxNumber([SeenLine('6', _b(0, 0, 9, 9), angle: 179)]), isNull);
    expect(boxNumber([SeenLine('6', _b(0, 0, 9, 9), angle: 182)]), isNull);
    // A slight tilt is upright under either angle convention.
    expect(boxNumber([SeenLine('9', _b(0, 0, 9, 9), angle: 358)]), 9);
    expect(boxNumber([SeenLine('9', _b(0, 0, 9, 9), angle: -3)]), 9);
    expect(
      boxNumber([
        SeenLine('6', _b(0, 0, 9, 9), angle: -178),
        SeenLine('1 5 1', _b(0, 0, 9, 9), angle: 2),
      ]),
      151,
    );
    expect(boxNumber([SeenLine('~ 9 ~', _b(0, 0, 9, 9))]), 9);
    expect(boxNumber([SeenLine('p. 9', _b(0, 0, 9, 9))]), isNull);
  });

  test('wide words count only upright, real, wide words', () {
    final lines = [
      SeenLine(
        'x',
        _b(0, 0, 1, 1),
        words: [
          ('Pasmo', _b(0, 0, 50, 10)),
          ('pionowe', _b(0, 0, 10, 50)),
          ('ab', _b(0, 0, 50, 10)),
          ('12345', _b(0, 0, 50, 10)),
          ('Żółć', _b(0, 0, 50, 10)),
        ],
      ),
    ];
    expect(wideWords(lines), 2);
  });

  group('choosePage mirrors the PC', () {
    PageChoice pick(
      List<int> found,
      PageContext context, {
      bool boxed = false,
    }) => choosePage([for (final v in found) _hit(v)], context, boxed: boxed);

    test('check photos look for the page asked for', () {
      expect(pick([3, 19], const PageContext(expected: 19)).hit?.value, 19);
      expect(
        pick([3], const PageContext(expected: 19)).reason,
        'page 19 not found on the photo',
      );
    });

    test('nothing plausible', () {
      expect(pick([], const PageContext()).reason, 'no page number found');
      expect(
        pick([3], const PageContext(after: 7)).reason,
        'no page after 7 found on the photo',
      );
      expect(
        pick([500], const PageContext(lastPage: 406)).reason,
        'no page number found',
      );
    });

    test('stops never take the bigger of two', () {
      expect(pick([3, 51], const PageContext(after: 7)).hit?.value, 51);
      expect(
        pick([51, 80], const PageContext(after: 7)).reason,
        'page number unclear (51 or 80)',
      );
    });

    test('starts take the number nearest the last end', () {
      expect(pick([3, 51, 51], const PageContext(near: 51)).hit?.value, 51);
      expect(
        pick([3, 51], const PageContext(near: 27)).reason,
        'page number unclear (3 or 51)',
      );
      expect(pick([45], const PageContext(near: 51)).hit?.value, 45);
      expect(
        pick([3], const PageContext(near: 51)).reason,
        'page 3 is far from p. 51, the last one',
      );
      expect(pick([3], const PageContext(near: 51), boxed: true).hit?.value, 3);
      expect(pick([7], const PageContext()).hit?.value, 7);
    });
  });

  test('unturn maps a turned, scaled box back to decoded pixels', () {
    // A 100x50 image scaled by 0.5; box in each turned frame.
    final box = _b(10, 20, 30, 40);
    expect(unturn(box, 0, 100, 50, 0.5), _b(20, 40, 60, 80));
    expect(unturn(box, 90, 100, 50, 0.5), _b(40, 40, 80, 80));
    expect(unturn(box, 180, 100, 50, 0.5), _b(140, 20, 180, 60));
    expect(unturn(box, 270, 100, 50, 0.5), _b(120, 20, 160, 60));
  });

  test('toStored undoes every EXIF orientation of a 60x40 file', () {
    // A dot at stored (10, 5)-(11, 6), as PIL's exif_transpose moves it.
    final applied = {
      1: _b(10, 5, 11, 6),
      2: _b(49, 5, 50, 6),
      3: _b(49, 34, 50, 35),
      4: _b(10, 34, 11, 35),
      5: _b(5, 10, 6, 11),
      6: _b(34, 10, 35, 11),
      7: _b(34, 49, 35, 50),
      8: _b(5, 49, 6, 50),
    };
    for (final MapEntry(key: orientation, value: box) in applied.entries) {
      expect(
        toStored(box, orientation, 60, 40),
        _b(10, 5, 11, 6),
        reason: 'orientation $orientation',
      );
    }
  });
}
