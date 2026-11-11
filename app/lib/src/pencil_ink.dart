/// The pixel work under `pencil_find.dart`: a page shrunk to block means and
/// the paper level around each pixel (ports of `shrink`, `paper_map` and
/// helpers in `book_guard/_pencil_find.py`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// [v] rounded half up (the PC rounds the same way).
int nearest(double v) => (v + 0.5).floor();

/// [gray] (row-major, [width] x [height]) as the floor of the mean of each
/// [factor] x [factor] block.
(Int32List, int, int) shrink(
  Uint8List gray,
  int width,
  int height,
  int factor,
) {
  final rows = height ~/ factor;
  final cols = width ~/ factor;
  final out = Int32List(rows * cols);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      var sum = 0;
      for (var y = 0; y < factor; y++) {
        final base = (r * factor + y) * width + c * factor;
        for (var x = 0; x < factor; x++) {
          sum += gray[base + x];
        }
      }
      out[r * cols + c] = sum ~/ (factor * factor);
    }
  }
  return (out, rows, cols);
}

/// The mean of [small] over the window of [radius] around each pixel.
Float64List paperMap(Int32List small, int rows, int cols, int radius) {
  final total = Int64List((rows + 1) * (cols + 1));
  for (var r = 0; r < rows; r++) {
    var run = 0;
    for (var c = 0; c < cols; c++) {
      run += small[r * cols + c];
      total[(r + 1) * (cols + 1) + c + 1] = total[r * (cols + 1) + c + 1] + run;
    }
  }
  final out = Float64List(rows * cols);
  for (var r = 0; r < rows; r++) {
    final top = math.max(r - radius, 0);
    final bottom = math.min(r + radius + 1, rows);
    for (var c = 0; c < cols; c++) {
      final left = math.max(c - radius, 0);
      final right = math.min(c + radius + 1, cols);
      final ink =
          total[bottom * (cols + 1) + right] -
          total[top * (cols + 1) + right] -
          total[bottom * (cols + 1) + left] +
          total[top * (cols + 1) + left];
      out[r * cols + c] = ink / ((bottom - top) * (right - left));
    }
  }
  return out;
}

/// The median of [values] (the lower middle one).
int median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[(sorted.length - 1) ~/ 2];
}
