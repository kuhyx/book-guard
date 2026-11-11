import 'dart:io';
import 'dart:typed_data';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/pencil_scan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pencil_cases.dart';

/// A line of one word, [conf] sure, in a box [height] tall.
SeenLine _line(
  String word,
  int left,
  int top,
  int width,
  int height, [
  double conf = 0.9,
]) {
  final box = (left: left, top: top, right: left + width, bottom: top + height);
  return SeenLine(word, box, words: [(word, box)], confidence: [conf]);
}

/// [count] sure words stacked in one column starting at [left].
List<SeenLine> _column(int count, int left, {int height = 16}) => [
  for (var i = 0; i < count; i++)
    _line('filozofia', left, 10 + 20 * i, 90, height),
];

void main() {
  group('the body of the page the pencil number is measured from', () {
    test('is the box and line height of the confidently read text', () {
      final body = pencilBody(_column(12, 100))!;
      expect(body.left, 100);
      expect(body.top, 10);
      expect(body.right, 190);
      expect(body.bottom, 10 + 20 * 11 + 16);
      expect(body.line, 16);
    });

    test('is the column with the most words, not the facing page', () {
      final lines = [..._column(3, 5), ..._column(12, 300)];
      expect(pencilBody(lines)!.left, 300);
    });

    test('is null where the turn is unsure: fewer than ten sure words', () {
      expect(pencilBody(_column(9, 100)), isNull);
      final unsure = [
        for (var i = 0; i < 12; i++) _line('filozofia', 1, 1, 9, 9, 0.5),
      ];
      expect(pencilBody(unsure), isNull);
    });

    test('counts only words of 3+ letters', () {
      final digits = [
        for (var i = 0; i < 12; i++) _line('1234', 10, 10 + 20 * i, 40, 16),
      ];
      expect(pencilBody(digits), isNull);
    });

    test(
      'the line height is the median of the words (mean of two middles)',
      () {
        final lines = [
          for (var i = 0; i < 10; i++)
            _line('filozofia', 100, 10 + 30 * i, 90, i < 5 ? 10 : 20),
        ];
        expect(pencilBody(lines)!.line, 15);
      },
    );
  });

  group('the number read off the upright preview', () {
    final net = File('assets/pencil_digits.bin').readAsBytesSync();

    (Uint8List, PencilBody) preview(String name) => pencilCaseJpeg(name);

    test('a pencilled 612 and 1 survive the preview JPEG', () async {
      for (final (name, want) in [
        ('pencil_612', 612),
        ('pencil_1', 1),
        ('pencil_29', 29),
      ]) {
        final (jpeg, body) = preview(name);
        expect(await pencilFromPreview(net, jpeg, body), want, reason: name);
      }
    });

    test('no pencil on a printed page or a blank margin is null', () async {
      for (final name in ['print_9_ornaments', 'print_502', 'blank_margin']) {
        final (jpeg, body) = preview(name);
        expect(await pencilFromPreview(net, jpeg, body), isNull, reason: name);
      }
    });

    test('an image that cannot be decoded is null, never a throw', () async {
      final (_, body) = preview('pencil_612');
      expect(
        await pencilFromPreview(net, Uint8List.fromList([1, 2, 3]), body),
        isNull,
      );
    });
  });
}
