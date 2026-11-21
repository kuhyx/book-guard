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

  /// Tesseract's whole-page read finds [number] in the margin (where the
  /// pencil is) and the crop re-read agrees.
  void tesseractReads(String number) => answer(
    (psm) => psm == 3
        ? [
            ..._prose(),
            [_word(number, 150, 200, 170, 216, 0.95)],
          ]
        : [
            [_word(number, 5, 5, 45, 40, 0.9)],
          ],
  );

  // 2026-11-21: Tesseract read a pencilled 237 as 234 and offered it as a
  // one-tap hit; the digit net never ran because a hit existed.
  test('a pencil Tesseract misreads is no hit: the net pre-fills', () async {
    tesseractReads('671'); // what Tesseract makes of the pencilled 612
    final scan = (await reader.scan(pencilCaseJpeg('pencil_612').$1))!;
    expect(scan.hits, isEmpty);
    expect(scan.previewHits, isEmpty);
    expect(scan.pencilPage, 612);
  });

  test('a hit the pencil reading agrees with stays a hit', () async {
    tesseractReads('612');
    final scan = (await reader.scan(pencilCaseJpeg('pencil_612').$1))!;
    expect(scan.hits.map((h) => h.value), everyElement(612));
    expect(scan.hits, isNotEmpty);
    expect(scan.previewHits, hasLength(scan.hits.length));
    expect(scan.pencilPage, 612);
  });

  test('a printed number on a page with no pencil stays a hit', () async {
    tesseractReads('19');
    final scan = (await reader.scan(pencilCaseJpeg('blank_margin').$1))!;
    expect(scan.hits.first.value, 19);
    expect(scan.pencilPage, isNull);
  });

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
