import 'dart:io';

import 'package:book_guard_app/src/page_reader.dart' as api;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cache;
  late List<Map<Object?, Object?>> calls;
  late TesseractPageReader reader;

  void answer(Object? Function(int psm, int call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final args = (call.arguments as Map).cast<Object?, Object?>();
          expect(File(args['path']! as String).existsSync(), isTrue);
          calls.add(args);
          return reply(args['psm']! as int, calls.length);
        });
  }

  setUp(() {
    cache = Directory.systemTemp.createTempSync('tess_test');
    calls = [];
    reader = TesseractPageReader(cacheDir: () async => cache);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    cache.deleteSync(recursive: true);
  });

  final photo = img.encodeJpg(img.Image(width: 200, height: 100));

  test('the platform reader is Tesseract', () {
    expect(api.createPageReader(), isA<TesseractPageReader>());
  });

  test('an unreadable photo is null', () async {
    expect(await reader.scan(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test(
    'the turn with the most upright words wins; its number is a hit',
    () async {
      // Calls 1-4 are the four turns of the whole page; turn 90 (call 2) reads.
      answer((psm, call) {
        if (call != 2) return <Object?>[];
        return [
          ..._prose(),
          [_word('19', 60, 180, 80, 196, 0.95)],
        ];
      });
      final scan = (await reader.scan(photo))!;
      // The four turns, then the number re-read from its crop.
      expect(calls.map((c) => c['psm']), [3, 3, 3, 3, 7]);
      expect(scan.turn, 90);
      expect((scan.previewWidth, scan.previewHeight), (100, 200));
      expect(scan.hits.single.value, 19);
      expect(scan.previewHits.single, (
        left: 60,
        top: 180,
        right: 80,
        bottom: 196,
      ));
      expect(scan.preview, isNotEmpty);
      expect(scan.millis, greaterThanOrEqualTo(0));
      expect(cache.listSync(), isEmpty);
    },
  );

  test('an upright page is not read in the other turns', () async {
    answer(
      (psm, call) => [
        [
          for (var i = 0; i < 30; i++)
            _word('wordy', 40 * i, 100, 40 * i + 30, 110, 0.9),
        ],
      ],
    );
    final scan = (await reader.scan(photo))!;
    expect(scan.turn, 0);
    expect(
      calls.where((c) => c['psm'] == 3 && c['model'] == 'fast'),
      hasLength(1),
    );
  });

  test('a number is re-read from a full-resolution crop', () async {
    answer((psm, call) {
      if (psm == 7) {
        return [
          [_word('151', 5, 5, 45, 40, 0.9)],
        ];
      }
      return [
        ..._prose(),
        [_word('161', 90, 85, 99, 99, 0.9)],
      ];
    });
    final scan = (await reader.scan(photo))!;
    expect(scan.hits.single.value, 151);
    expect(scan.previewHits.single.left, 90);
  });

  test('no number on the whole page: the edge strips are read', () async {
    answer((psm, call) {
      if (psm == 3) return call == 1 ? _prose() : <Object?>[];
      // The first window (top strip, left) holds a sure 7 and an unsure 8.
      return call == 5
          ? [
              [_word('7', 20, 5, 30, 25, 0.9)],
              [_word('8', 40, 5, 50, 25, 0.3)],
            ]
          : <Object?>[];
    });
    final scan = (await reader.scan(photo))!;
    expect(scan.turn, 0);
    expect(calls.where((c) => c['psm'] == 6), isNotEmpty);
    expect(scan.hits.map((h) => h.value), [7]);
  });

  test('a number on the page skips the edge strips', () async {
    answer(
      (psm, call) => call == 1
          ? [
              ..._prose(),
              [_word('51', 90, 85, 99, 99, 0.9)],
            ]
          : <Object?>[],
    );
    final scan = (await reader.scan(photo))!;
    expect(scan.hits.single.value, 51);
    expect(calls.where((c) => c['psm'] == 6), isEmpty);
  });

  test('a boxed number is read as one line, then as one character', () async {
    var reading = false;
    answer((psm, call) {
      if (!reading) return _prose();
      if (psm == 7) return <Object?>[];
      return [
        [_word('7', 5, 5, 25, 40, 0.9)],
      ];
    });
    final scan = (await reader.scan(photo))!;
    calls.clear();
    reading = true;
    final number = await reader.readBox(photo, scan, (
      left: 40,
      top: 40,
      right: 60,
      bottom: 60,
    ));
    expect(number, 7);
    expect(calls.map((c) => c['psm']), [7, 10]);
  });

  test('a boxed number needs only the first read when it works', () async {
    var reading = false;
    answer(
      (psm, call) => reading
          ? [
              [_word('151', 5, 5, 45, 40, 0.9)],
            ]
          : _prose(),
    );
    final scan = (await reader.scan(photo))!;
    calls.clear();
    reading = true;
    final number = await reader.readBox(photo, scan, (
      left: 40,
      top: 40,
      right: 60,
      bottom: 60,
    ));
    expect(number, 151);
    expect(calls, hasLength(1));
  });
}
