/// Full-resolution cuts of a photo for Tesseract: the crop around a number
/// (re-read where the 1600 px page read can drop a digit) and the strips
/// near the page's top and bottom edge, for a small lone page number.
///
/// Everything here is plain Dart and runs inside `Isolate.run`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:book_guard_app/src/page_number.dart' show Box;
import 'package:book_guard_app/src/page_prep.dart';
import 'package:image/image.dart' as img;

const _boxPad = 0.25;

// Edge strips: the outer fifth (and a little more) of the upright page, at
// up to _workEdge pixels, cut into windows Tesseract can still lay out (a
// whole noisy strip makes it see nothing -- the lone "7" of p7_start).
const _bandFrac = 0.22;
const _workEdge = 3200;
const _windowWidth = 1000;
const _windowStep = 500;

/// A strip of the upright page for Tesseract: [ink] cut at ([left], [top])
/// of a page that is [workWidth] pixels wide.
class EdgeWindow {
  /// Creates a window.
  const new(this.ink, this.left, this.top, this.workWidth);

  /// The flattened strip.
  final Gray ink;

  /// Its left edge on the page, in working pixels.
  final int left;

  /// Its top edge on the page, in working pixels.
  final int top;

  /// The page's width in working pixels (the unit of [left] and [top]).
  final int workWidth;
}

/// The full-resolution crops around the job's boxes (decoded pixels), each
/// turned like the page it was drawn on and flattened: one isolate trip for
/// every number re-read.
List<Gray> cropsForBoxes((img.Image, List<Box>, int) job) {
  final (decoded, boxes, turn) = job;
  return [for (final box in boxes) cropForBox((decoded, box, turn))];
}

/// The full-resolution crop around the job's box (decoded pixels), turned
/// like the page it was drawn on and flattened.
Gray cropForBox((img.Image, Box, int) job) {
  final (decoded, box, turn) = job;
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
  return flatten(img.copyRotate(crop, angle: turn));
}

/// [cropForBox] on a photo not decoded yet (a box drawn on the review).
Gray cropFromJpeg((Uint8List, Box, int) job) {
  final (bytes, box, turn) = job;
  return cropForBox((img.decodeJpg(bytes)!, box, turn));
}

img.Image _band(img.Image page, {required bool top}) {
  final height = (page.height * _bandFrac).round();
  return img.copyCrop(
    page,
    x: 0,
    y: top ? 0 : page.height - height,
    width: page.width,
    height: height,
  );
}

/// The top and bottom strips of a photo turned by the job's degrees,
/// flattened and cut into overlapping windows.
List<EdgeWindow> edgeWindows((img.Image, int) job) {
  final (decoded, turn) = job;
  final scale = math.min(
    1,
    _workEdge / math.max(decoded.width, decoded.height),
  );
  final page = img.copyRotate(
    img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      interpolation: img.Interpolation.average,
    ),
    angle: turn,
  );
  final windows = <EdgeWindow>[];
  for (final topStrip in [true, false]) {
    final band = _band(page, top: topStrip);
    final top = topStrip ? 0 : page.height - band.height;
    var left = 0;
    while (true) {
      final width = math.min(_windowWidth, band.width - left);
      windows.add(
        EdgeWindow(
          flatten(
            img.copyCrop(
              band,
              x: left,
              y: 0,
              width: width,
              height: band.height,
            ),
          ),
          left,
          top,
          page.width,
        ),
      );
      if (left + width >= band.width) break;
      left += _windowStep;
    }
  }
  return windows;
}
