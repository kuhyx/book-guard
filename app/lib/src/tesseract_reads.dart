import 'dart:isolate';

import 'package:book_guard_app/src/page_crops.dart';
import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_prep.dart';
import 'package:book_guard_app/src/tesseract_lines.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// [work] on [job] in its own isolate. A top-level function, so the closure
/// sent there holds only [work] and [job], never the caller's futures (which
/// cannot cross).
Future<R> apart<J, R>(R Function(J) work, J job) =>
    Isolate.run(() => work(job));

const _pageLayout = 3; // Tesseract's PSM_AUTO
const _oneLine = 7;
const _oneChar = 10;
const _block = 6;
// A number read from a window must be sure: a window is mostly paper and
// stray marks read as digits.
const _windowSure = 0.6;

/// The reads `TesseractChannel.kt` does: a page, the edge windows, number
/// crops. The native side runs four engines, so reads started together run
/// together; each gets the same pixels as when they ran one by one.
abstract class TesseractReads {
  /// Creates the reads over [channel].
  new(this.channel);

  /// The native side, `TesseractChannel.kt`.
  final MethodChannel channel;

  /// Which model reads: the small fast one, or the full one.
  String model = 'fast';

  /// Milliseconds each stage of the last scan took (for page_truth runs).
  final stages = <String, int>{};

  /// [run], its time added to [stage].
  Future<T> timed<T>(String stage, Future<T> Function() run) async {
    final watch = Stopwatch()..start();
    try {
      return await run();
    } finally {
      stages[stage] = (stages[stage] ?? 0) + watch.elapsedMilliseconds;
    }
  }

  /// The lines Tesseract reads in [ink], handed over as the q92 JPEG it was
  /// tuned on ([inkJpeg]). [tag] names the read for logs and tests.
  Future<List<SeenLine>> lines(
    Gray ink, {
    int psm = _pageLayout,
    double minConfidence = 0,
    String tag = '',
  }) async {
    final model = this.model; // a later switch to "full" is not this read's
    final jpeg = await apart(inkJpeg, ink);
    final raw = await channel.invokeMethod<Object?>('recognize', {
      'tag': tag,
      'jpeg': jpeg,
      'psm': psm,
      'model': model,
    });
    return linesFromChannel(raw, minConfidence: minConfidence);
  }

  /// [ink] turned [turn] degrees and read as a page.
  Future<List<SeenLine>> readTurn(Gray ink, int turn) async {
    final turned = turn == 0
        ? ink
        : await timed('${model}_turn$turn', () => apart(turnGray, (ink, turn)));
    return await timed('${model}_ocr$turn', () => lines(turned, tag: '$turn'));
  }

  /// Lone numbers in the upright page's edge strips, read at full
  /// resolution, in the preview's pixels -- for the small number Tesseract
  /// cannot see on the whole page. Every window is read at once.
  Future<List<SeenLine>> edgeLines(
    img.Image decoded,
    int turn,
    int previewWidth,
  ) async {
    final windows = await apart(edgeWindows, (decoded, turn));
    final read = await Future.wait([
      for (final w in windows)
        lines(w.ink, psm: _block, minConfidence: _windowSure),
    ]);
    return withoutRepeats([
      for (final (i, w) in windows.indexed)
        for (final line in read[i])
          placeLine(line, w.left, w.top, previewWidth / w.workWidth),
    ]);
  }

  /// Each box's number, cropped from [decoded] at full resolution, turned
  /// [turn] and read as one line; all at once.
  Future<List<int?>> readCrops(
    img.Image decoded,
    List<Box> boxes,
    int turn,
  ) async {
    if (boxes.isEmpty) return const [];
    final inks = await apart(cropsForBoxes, (decoded, boxes, turn));
    return [
      for (final found in await Future.wait([
        for (final ink in inks) lines(ink, psm: _oneLine),
      ]))
        boxNumber(found),
    ];
  }

  /// The number in [box] (decoded pixels) of the photo [bytes], read as one
  /// line; a crop that shows no line is read again as one glyph (a box the
  /// reader drew).
  Future<int?> readCrop(Uint8List bytes, Box box, int turn) async {
    final ink = await apart(cropFromJpeg, (bytes, box, turn));
    final line = boxNumber(await lines(ink, psm: _oneLine));
    if (line != null) return line;
    return boxNumber(await lines(ink, psm: _oneChar));
  }
}
