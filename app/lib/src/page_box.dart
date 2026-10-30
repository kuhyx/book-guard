/// Page-number boxes moved between the frames a photo passes through:
/// the turned preview, the decoded (EXIF-applied) pixels, and the stored
/// file the PC is sent.
library;

import 'dart:math' as math;

import 'package:book_guard_app/src/page_number.dart' show Box;

/// [box] in an image that was scaled by [scale] and then turned [turn]
/// degrees clockwise (an image [width] x [height] *before* the turn)
/// -> the same box in the decoded, EXIF-applied pixels.
Box unturn(Box box, int turn, int width, int height, double scale) {
  (double, double) back(double x, double y) => switch (turn) {
    90 => (y, height - x),
    180 => (width - x, height - y),
    270 => (width - y, x),
    _ => (x, y),
  };
  return _bounds(
    back(box.left.toDouble(), box.top.toDouble()),
    back(box.right.toDouble(), box.bottom.toDouble()),
    1 / scale,
  );
}

/// [box] in the EXIF-applied pixels of a file stored [storedWidth] x
/// [storedHeight] with EXIF [orientation] -> the stored pixels, which is
/// what the PC is sent (it applies EXIF itself, as PIL does).
Box toStored(Box box, int orientation, int storedWidth, int storedHeight) {
  final w = storedWidth.toDouble();
  final h = storedHeight.toDouble();
  (double, double) back(double x, double y) => switch (orientation) {
    2 => (w - x, y),
    3 => (w - x, h - y),
    4 => (x, h - y),
    5 => (y, x),
    6 => (y, h - x),
    7 => (w - y, h - x),
    8 => (w - y, x),
    _ => (x, y),
  };
  return _bounds(
    back(box.left.toDouble(), box.top.toDouble()),
    back(box.right.toDouble(), box.bottom.toDouble()),
    1,
  );
}

Box _bounds((double, double) a, (double, double) b, double factor) => (
  left: (math.min(a.$1, b.$1) * factor).floor(),
  top: (math.min(a.$2, b.$2) * factor).floor(),
  right: (math.max(a.$1, b.$1) * factor).ceil(),
  bottom: (math.max(a.$2, b.$2) * factor).ceil(),
);
