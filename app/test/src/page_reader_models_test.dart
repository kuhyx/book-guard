import 'dart:io';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader_tesseract.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _channel = MethodChannel('book_guard/tesseract');

Map<String, Object> _word(String text, int l, int t, int r, int b, num c) => {
  'text': text,
  'left': l,
  'top': t,
  'right': r,
  'bottom': b,
  'conf': c,
};

/// Words that read as an upright page (wide, 3+ letters).
List<List<Map<String, Object>>> _prose() => [
  [
    _word('Hello', 10, 100, 90, 120, 0.9),
    _word('world', 100, 100, 180, 120, 0.9),
  ],
];

/// The recheck of a number from its crop, and the full model as a second
/// opinion (`TesseractPageReader`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cache;
  late List<Map<Object?, Object?>> calls;
  late TesseractPageReader reader;

  void answer(Object? Function(int psm, int call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final args = (call.arguments as Map).cast<Object?, Object?>();
          calls.add(args);
          return reply(args['psm']! as int, calls.length);
        });
  }

  setUp(() {
    cache = Directory.systemTemp.createTempSync('tess_models_test');
    calls = [];
    reader = TesseractPageReader(cacheDir: () async => cache);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    cache.deleteSync(recursive: true);
  });

  final photo = img.encodeJpg(img.Image(width: 200, height: 100));

  test('a crop that drops a digit never replaces the page reading', () async {
    // The crop read "12" or "0" for 612 and 611 on a better model.
    for (final (page, crop) in [('612', '12'), ('611', '0'), ('51', '9')]) {
      answer((psm, call) {
        if (psm == 7) {
          return [
            [_word(crop, 5, 5, 45, 40, 0.9)],
          ];
        }
        return [
          ..._prose(),
          [_word(page, 90, 85, 99, 99, 0.9)],
        ];
      });
      final scan = (await reader.scan(photo))!;
      expect(scan.hits.single.value, int.parse(page));
    }
  });

  test('a crop that finds the digits the page read missed wins', () async {
    // 2026-11-09 on a bigger model: the whole page read "2" for 502.
    answer((psm, call) {
      if (psm == 7) {
        return [
          [_word('502', 5, 5, 45, 40, 0.9)],
        ];
      }
      return [
        ..._prose(),
        [_word('2', 90, 85, 99, 99, 0.9)],
      ];
    });
    expect((await reader.scan(photo))!.hits.single.value, 502);
  });

  group('the full model, when the fast one has nothing usable', () {
    const stop = PageContext(after: 556, lastPage: 611);
    Object? answerBy(String model, String number, int psm) => psm == 7
        ? <Object?>[]
        : [
            ..._prose(),
            [_word(number, 90, 85, 99, 99, 0.9)],
          ];

    test(
      'p. 611: the fast model read a stray 3, the full one the page',
      () async {
        answer(
          (psm, _) => answerBy(
            calls.last['model']! as String,
            calls.last['model'] == 'full' ? '611' : '3',
            psm,
          ),
        );
        final scan = (await reader.scan(photo, context: stop))!;
        expect(scan.hits.map((h) => h.value), [611]);
        expect(calls.where((c) => c['model'] == 'full'), isNotEmpty);
      },
    );

    test('a usable fast reading is final', () async {
      answer((psm, _) => answerBy('fast', '51', psm));
      final scan = (await reader.scan(
        photo,
        context: const PageContext(after: 7),
      ))!;
      expect(scan.hits.single.value, 51);
      expect(calls.where((c) => c['model'] == 'full'), isEmpty);
    });

    test('neither model usable: the fast reading stands', () async {
      answer((psm, _) => answerBy('x', '3', psm));
      final scan = (await reader.scan(photo, context: stop))!;
      expect(scan.hits.single.value, 3);
      expect(calls.where((c) => c['model'] == 'full'), isNotEmpty);
    });
  });
}
