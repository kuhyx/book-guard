import 'dart:io';
import 'dart:isolate';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_prep.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/tesseract_lines.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Tesseract on the phone: no network, no PC, no Claude.
PageReader? createPageReader() => TesseractPageReader();

const _turns = [0, 90, 180, 270];
const _pageLayout = 3; // Tesseract's PSM_AUTO
const _oneLine = 7;
const _oneChar = 10;
// A number read from a window must be sure: a window is mostly paper and
// stray marks read as digits.
const _windowSure = 0.6;
// This many sure, wide words is an upright page: the other turns are not
// read at all (each costs a second on the phone).
const _uprightEnough = 25;
// Hits re-read from a crop: a page seldom has more than a spread's two
// numbers, and each re-read costs a decode of the photo.
const _recheckMax = 4;

/// Tesseract4Android through the `book_guard/tesseract` channel, over JPEG
/// files written to the cache folder (the native side reads files).
class TesseractPageReader implements PageReader {
  /// Creates the reader; [channel] and [cacheDir] are for tests.
  new({
    this.channel = const MethodChannel('book_guard/tesseract'),
    this.cacheDir = getTemporaryDirectory,
  });

  /// The native side, `TesseractChannel.kt`.
  final MethodChannel channel;

  /// Where the JPEGs handed to the native side are written.
  final Future<Directory> Function() cacheDir;

  Future<List<SeenLine>> _lines(
    Uint8List jpeg,
    String tag, {
    int psm = _pageLayout,
    double minConfidence = 0,
  }) async {
    final dir = await cacheDir();
    final file = File('${dir.path}/page_$tag.jpg');
    await file.writeAsBytes(jpeg, flush: true);
    try {
      final raw = await channel.invokeMethod<Object?>('recognize', {
        'path': file.path,
        'psm': psm,
      });
      return linesFromChannel(raw, minConfidence: minConfidence);
    } finally {
      await file.delete();
    }
  }

  /// Lone numbers in the upright page's edge strips, read at full
  /// resolution, in the preview's pixels -- for the small number Tesseract
  /// cannot see on the whole page.
  Future<List<SeenLine>> _edgeLines(
    Uint8List bytes,
    int turn,
    int previewWidth,
  ) async {
    final windows = await Isolate.run(() => edgeWindows((bytes, turn)));
    final found = <SeenLine>[];
    for (final (i, window) in windows.indexed) {
      final ratio = previewWidth / window.workWidth;
      final lines = await _lines(
        window.jpeg,
        'edge$i',
        psm: 6,
        minConfidence: _windowSure,
      );
      found.addAll([
        for (final line in lines)
          placeLine(line, window.left, window.top, ratio),
      ]);
    }
    return withoutRepeats(found);
  }

  @override
  Future<PageScan?> scan(Uint8List bytes) async {
    final watch = Stopwatch()..start();
    final Prepared prepared;
    try {
      prepared = await Isolate.run(() => preparePage(bytes));
    } on Exception {
      return null;
    }
    var best = -1;
    var bestTurn = 0;
    var bestLines = <SeenLine>[];
    for (final (i, turn) in _turns.indexed) {
      final lines = await _lines(prepared.inks[i], '$turn');
      final score = wideWords(sureWords(lines));
      if (score > best) {
        (best, bestTurn, bestLines) = (score, turn, lines);
      }
      if (score >= _uprightEnough) break;
    }
    final sideways = bestTurn == 90 || bestTurn == 270;
    Box toDecodedBox(Box box) =>
        unturn(box, bestTurn, prepared.width, prepared.height, prepared.scale);
    Box toStoredBox(Box box) => toStored(
      toDecodedBox(box),
      prepared.orientation,
      prepared.storedWidth,
      prepared.storedHeight,
    );
    final width = sideways ? prepared.height : prepared.width;
    final height = sideways ? prepared.width : prepared.height;
    var numbers = numberLines(bestLines, height);
    if (numbers.isEmpty) {
      numbers = numberLines(await _edgeLines(bytes, bestTurn, width), height);
    }
    // The whole page is read at 1600 px, where a 151 can read as 161: each
    // number is read again from its own full-resolution crop.
    numbers = [
      for (final (number, line) in numbers.take(_recheckMax))
        (
          await _readCrop(bytes, toDecodedBox(line.box), bestTurn) ?? number,
          line,
        ),
    ];
    return PageScan(
      turn: bestTurn,
      hits: [
        for (final (number, line) in numbers)
          NumberHit(number, toStoredBox(line.box)),
      ],
      previewHits: [for (final (_, line) in numbers) line.box],
      preview: prepared.jpegs[_turns.indexOf(bestTurn)],
      previewWidth: width,
      previewHeight: height,
      toStoredBox: toStoredBox,
      toDecodedBox: toDecodedBox,
      millis: watch.elapsedMilliseconds,
    );
  }

  /// The number in [decoded] (decoded pixels), cropped from the photo at
  /// full resolution, turned [turn] and read as one line, else one glyph.
  Future<int?> _readCrop(Uint8List bytes, Box decoded, int turn) async {
    final jpeg = await Isolate.run(() => cropForBox((bytes, decoded, turn)));
    final line = boxNumber(await _lines(jpeg, 'box', psm: _oneLine));
    return line ?? boxNumber(await _lines(jpeg, 'box', psm: _oneChar));
  }

  @override
  Future<int?> readBox(Uint8List bytes, PageScan scan, Box previewBox) =>
      _readCrop(bytes, scan.toDecodedBox(previewBox), scan.turn);
}
