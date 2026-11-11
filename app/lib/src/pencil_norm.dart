/// One pencilled glyph, put into the shape the digit network was trained on
/// (`book_guard/_pencil_norm.py`, ported line for line; keep them in step
/// with `test/fixtures/pencil_goldens.json`).
///
/// MNIST-class: a 28x28 picture, the digit 20 px on its long side, centred by
/// its centre of mass. Pencil is thin, so the stroke is first widened to a
/// share of the glyph's size, then the glyph is squeezed to 20 px.
library;

import 'dart:typed_data';

/// Side of the network's picture.
const pencilField = 28;
const _glyph = 20;
const double _centre = (pencilField - 1) / 2;

/// A bool picture, row by row (1 = ink).
class Mask {
  /// Creates a mask of [height] x [width]; [cells] defaults to all clear.
  new(this.height, this.width, [Uint8List? cells])
    : cells = cells ?? Uint8List(height * width);

  /// Rows.
  final int height;

  /// Columns.
  final int width;

  /// Row-major cells, 0 or 1.
  final Uint8List cells;

  /// Whether (y, x) is ink; outside the mask is clear.
  bool at(int y, int x) =>
      y >= 0 && y < height && x >= 0 && x < width && cells[y * width + x] != 0;

  /// The number of ink cells.
  int get area => cells.fold(0, (n, v) => n + v);
}

/// Mean stroke width: twice the area over the edge pixels (the glyph's size
/// when there is no edge).
double strokeWidth(Mask mask) {
  var edge = 0;
  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      if (!mask.at(y, x)) continue;
      final inside =
          mask.at(y - 1, x) &&
          mask.at(y + 1, x) &&
          mask.at(y, x - 1) &&
          mask.at(y, x + 1);
      if (!inside) edge++;
    }
  }
  if (edge == 0) {
    return (mask.height > mask.width ? mask.height : mask.width) + 0.0;
  }
  return 2.0 * mask.area / edge;
}

/// [mask] grown by [radius] pixels in every direction (square kernel).
Mask thicken(Mask mask, int radius) {
  if (radius <= 0) return mask;
  final h = mask.height + 2 * radius;
  final w = mask.width + 2 * radius;
  final rows = Mask(h, w);
  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      if (!mask.at(y, x)) continue;
      for (var d = 0; d <= 2 * radius; d++) {
        rows.cells[(y + d) * w + x + radius] = 1;
      }
    }
  }
  final out = Mask(h, w);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (rows.cells[y * w + x] == 0) continue;
      for (var d = -radius; d <= radius; d++) {
        final nx = x + d;
        if (nx >= 0 && nx < w) out.cells[y * w + nx] = 1;
      }
    }
  }
  return out;
}

/// The source range `[low, high)` behind each of [target] cells.
(List<int>, List<int>) _ranges(int source, int target) {
  final low = <int>[];
  final high = <int>[];
  for (var cell = 0; cell < target; cell++) {
    final lo = cell * source ~/ target;
    final hi = ((cell + 1) * source + target - 1) ~/ target;
    low.add(lo);
    high.add(hi > lo + 1 ? hi : lo + 1);
  }
  return (low, high);
}

/// [mask] as a [height] x [width] picture of ink shares: each cell is the
/// share of ink in the block of pixels behind it.
List<double> squeeze(Mask mask, int height, int width) {
  final (rowLow, rowHigh) = _ranges(mask.height, height);
  final (colLow, colHigh) = _ranges(mask.width, width);
  final out = List<double>.filled(height * width, 0);
  for (var i = 0; i < height; i++) {
    for (var j = 0; j < width; j++) {
      var ink = 0;
      for (var y = rowLow[i]; y < rowHigh[i]; y++) {
        for (var x = colLow[j]; x < colHigh[j]; x++) {
          if (mask.cells[y * mask.width + x] != 0) ink++;
        }
      }
      out[i * width + j] =
          ink / ((rowHigh[i] - rowLow[i]) * (colHigh[j] - colLow[j]));
    }
  }
  return out;
}

/// [picture] (28x28, row-major) moved by whole pixels so its centre of mass
/// is the field's.
List<double> recentre(List<double> picture) {
  var mass = 0.0;
  var my = 0.0;
  var mx = 0.0;
  for (var y = 0; y < pencilField; y++) {
    for (var x = 0; x < pencilField; x++) {
      final v = picture[y * pencilField + x];
      mass += v;
      my += v * y;
      mx += v * x;
    }
  }
  if (mass <= 0) return picture;
  final shiftY = (_centre - my / mass + 0.5).floor();
  final shiftX = (_centre - mx / mass + 0.5).floor();
  final moved = List<double>.filled(pencilField * pencilField, 0);
  for (var y = 0; y < pencilField; y++) {
    for (var x = 0; x < pencilField; x++) {
      final sy = y - shiftY;
      final sx = x - shiftX;
      if (sy < 0 || sy >= pencilField || sx < 0 || sx >= pencilField) continue;
      moved[y * pencilField + x] = picture[sy * pencilField + sx];
    }
  }
  return moved;
}

/// The 28x28 picture of a glyph [mask] cut tight to its box; strokes thinner
/// than [widthFrac] of the glyph's long side are widened to it.
List<double> normalise(Mask mask, double widthFrac) {
  final side = mask.height > mask.width ? mask.height : mask.width;
  final grow = ((widthFrac * side - strokeWidth(mask)) / 2 + 0.5).floor();
  final grown = thicken(mask, grow < 0 ? 0 : grow);
  final big = grown.height > grown.width ? grown.height : grown.width;
  final scale = _glyph / big;
  final h = (grown.height * scale + 0.5).floor();
  final w = (grown.width * scale + 0.5).floor();
  final height = h < 1 ? 1 : h;
  final width = w < 1 ? 1 : w;
  final squeezed = squeeze(grown, height, width);
  final top = (pencilField - height) ~/ 2;
  final left = (pencilField - width) ~/ 2;
  final field = List<double>.filled(pencilField * pencilField, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      field[(top + y) * pencilField + left + x] = squeezed[y * width + x];
    }
  }
  return recentre(field);
}
