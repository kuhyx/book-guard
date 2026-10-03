import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// ML Kit on the phone: no network, no PC, no Claude.
PageReader? createPageReader() => MlKitPageReader();

const _edge = 1600;
const _turns = [0, 90, 180, 270];
const _boxPad = 0.25;

/// The photo decoded once (off the UI thread), downscaled, in all four
/// orientations -- the camera's EXIF turn is wrong when it points straight
/// down at a book (the p. 51 photo of 2026-10-03).
@visibleForTesting
class Prepared {
  /// Creates the prepared photo.
  const new({
    required this.orientation,
    required this.storedWidth,
    required this.storedHeight,
    required this.width,
    required this.height,
    required this.scale,
    required this.jpegs,
  });

  /// The file's EXIF orientation (1 if none).
  final int orientation;

  /// The stored pixels' width, before EXIF.
  final int storedWidth;

  /// The stored pixels' height, before EXIF.
  final int storedHeight;

  /// The downscaled, EXIF-applied image's width, before any turn.
  final int width;

  /// The downscaled, EXIF-applied image's height, before any turn.
  final int height;

  /// downscaled / decoded.
  final double scale;

  /// One JPEG per turn: 0, 90, 180, 270 degrees clockwise.
  final List<Uint8List> jpegs;
}

int _orientation(Uint8List bytes) =>
    img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;

/// Decodes [bytes] once, downscaled, in all four turns.
@visibleForTesting
Prepared preparePage(Uint8List bytes) {
  final orientation = _orientation(bytes);
  final decoded = img.decodeJpg(bytes)!;
  final sideways = orientation >= 5 && orientation <= 8;
  final scale = math.min(1, _edge / math.max(decoded.width, decoded.height));
  final small = img.copyResize(
    decoded,
    width: (decoded.width * scale).round(),
    interpolation: img.Interpolation.average,
  );
  return Prepared(
    orientation: orientation,
    storedWidth: sideways ? decoded.height : decoded.width,
    storedHeight: sideways ? decoded.width : decoded.height,
    width: small.width,
    height: small.height,
    scale: small.width / decoded.width,
    jpegs: [
      for (final turn in _turns)
        img.encodeJpg(img.copyRotate(small, angle: turn), quality: 90),
    ],
  );
}

/// The full-resolution crop around the job's box (decoded pixels), turned
/// like the page it was drawn on.
@visibleForTesting
Uint8List cropForBox((Uint8List, Box, int) job) {
  final (bytes, box, turn) = job;
  final decoded = img.decodeJpg(bytes)!;
  final pad = (math.max(box.right - box.left, box.bottom - box.top) * _boxPad)
      .round();
  final left = math.max(0, box.left - pad);
  final top = math.max(0, box.top - pad);
  final crop = img.copyCrop(
    decoded,
    x: left,
    y: top,
    width: math.min(decoded.width, box.right + pad) - left,
    height: math.min(decoded.height, box.bottom + pad) - top,
  );
  return img.encodeJpg(img.copyRotate(crop, angle: turn), quality: 95);
}

Box _box(Rect rect) => (
  left: rect.left.floor(),
  top: rect.top.floor(),
  right: rect.right.ceil(),
  bottom: rect.bottom.ceil(),
);

/// ML Kit's Latin recogniser over JPEG files written to the cache folder.
class MlKitPageReader implements PageReader {
  final _recognizer = TextRecognizer();

  Future<List<SeenLine>> _lines(Uint8List jpeg, String tag) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/page_$tag.jpg');
    await file.writeAsBytes(jpeg, flush: true);
    try {
      final text = await _recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      return [
        for (final block in text.blocks)
          for (final line in block.lines)
            SeenLine(
              line.text,
              _box(line.boundingBox),
              words: [
                for (final e in line.elements) (e.text, _box(e.boundingBox)),
              ],
            ),
      ];
    } finally {
      await file.delete();
    }
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
      final lines = await _lines(prepared.jpegs[i], '$turn');
      final score = wideWords(lines);
      if (score > best) {
        (best, bestTurn, bestLines) = (score, turn, lines);
      }
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
    final height = sideways ? prepared.width : prepared.height;
    final numbers = numberLines(bestLines, height);
    return PageScan(
      turn: bestTurn,
      hits: [
        for (final line in numbers)
          NumberHit(int.parse(line.text.trim()), toStoredBox(line.box)),
      ],
      previewHits: [for (final line in numbers) line.box],
      preview: prepared.jpegs[_turns.indexOf(bestTurn)],
      previewWidth: sideways ? prepared.height : prepared.width,
      previewHeight: height,
      toStoredBox: toStoredBox,
      toDecodedBox: toDecodedBox,
      millis: watch.elapsedMilliseconds,
    );
  }

  @override
  Future<int?> readBox(Uint8List bytes, PageScan scan, Box previewBox) async {
    final decoded = scan.toDecodedBox(previewBox);
    final jpeg = await Isolate.run(
      () => cropForBox((bytes, decoded, scan.turn)),
    );
    final digits = (await _lines(jpeg, 'box'))
        .map((l) => l.text.replaceAll(RegExp(r'\s'), ''))
        .where((t) => RegExp(r'^\d{1,4}$').hasMatch(t));
    return digits.isEmpty ? null : int.parse(digits.first);
  }
}
