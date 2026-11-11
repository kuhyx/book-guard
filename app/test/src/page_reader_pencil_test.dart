import 'dart:io';

import 'package:book_guard_app/src/page_reader_tesseract.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pencil_cases.dart';

const _channel = MethodChannel('book_guard/tesseract');

Map<String, Object> _word(String text, int l, int t, int r, int b, num c) => {
  'text': text,
  'left': l,
  'top': t,
  'right': r,
  'bottom': b,
  'conf': c,
};

/// Sixteen sure words stacked in the golden canvas's text column: an
/// upright page to Tesseract.
List<List<Map<String, Object>>> _prose() => [
  for (var i = 0; i < 16; i++)
    [_word('filozofia', 32, 4 * i, 222, 4 * i + 16, 0.9)],
];

/// What the phone does with a page its printed reader finds no number on: a
/// pencilled one is kept as a suggestion for the keypad, never as a hit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cache;
  late TesseractPageReader reader;

  void answer(Object? Function(int psm) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final args = (call.arguments as Map).cast<Object?, Object?>();
          return reply(args['psm']! as int);
        });
  }

  setUp(() {
    cache = Directory.systemTemp.createTempSync('pencil_test');
    reader = TesseractPageReader(cacheDir: () async => cache);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    cache.deleteSync(recursive: true);
  });

  test(
    'a pencilled 612 on a page with no printed number is suggested',
    () async {
      answer((psm) => psm == 3 ? _prose() : <Object?>[]);
      final scan = (await reader.scan(pencilCaseJpeg('pencil_612').$1))!;
      expect(
        scan.hits,
        isEmpty,
      ); // never a hit: the user confirms on the keypad
      expect(scan.pencilPage, 612);
    },
  );

  test('a blank margin suggests nothing', () async {
    answer((psm) => psm == 3 ? _prose() : <Object?>[]);
    final scan = (await reader.scan(pencilCaseJpeg('blank_margin').$1))!;
    expect(scan.hits, isEmpty);
    expect(scan.pencilPage, isNull);
  });

  test(
    'a page whose printed number was found is not asked for pencil',
    () async {
      answer(
        (psm) => psm == 3
            ? [
                ..._prose(),
                [_word('19', 150, 200, 170, 216, 0.95)],
              ]
            : [
                [_word('19', 5, 5, 45, 40, 0.9)],
              ],
      );
      final scan = (await reader.scan(pencilCaseJpeg('pencil_612').$1))!;
      expect(scan.hits.first.value, 19);
      expect(scan.pencilPage, isNull);
    },
  );

  test('a page with too few sure words is not asked either', () async {
    answer(
      (psm) => psm == 3
          ? [
              [_word('filozofia', 40, 0, 130, 16, 0.9)],
            ]
          : <Object?>[],
    );
    final scan = (await reader.scan(pencilCaseJpeg('pencil_612').$1))!;
    expect(scan.pencilPage, isNull);
  });
}
