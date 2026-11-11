/// Finds a pencilled page number in the margin and reads it with the digit
/// network: port of `book_guard/_pencil_find.py` (see there for the why).
///
/// Given the upright page as gray pixels and where its text sits, it takes the
/// ink (darker than the paper around), joins strokes into patches, keeps a
/// patch only if it looks like pencil in empty paper, and reads each glyph at
/// three stroke widths. Anything doubtful is null: a wrong pre-fill is worse
/// than an empty keypad.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:book_guard_app/src/pencil_blob.dart';
import 'package:book_guard_app/src/pencil_ink.dart';
import 'package:book_guard_app/src/pencil_net.dart';
import 'package:book_guard_app/src/pencil_norm.dart';

const _unitPx = 16;
const _blur = 2.0;
const _inkStep = 12;
const _busy = 0.35;
const _print = 75;
const _printShare = 0.02;
const _minPeak = 30;
const _heightLow = 0.5;
const _heightHigh = 6.0;
const _maxWidth = 3.5;
const _maxPatches = 4;
const _mateReach = 4.0;
const _paperShare = 0.8;
const _fracs = [0.11, 0.14, 0.18];
const _sure = 0.75;
const _notADigit = 10;
const _maxDigits = 4;

Mask _glyphMask(Float64List diff, int rows, int cols, Box glyph) {
  final top = math.max(0, glyph.top - 2);
  final left = math.max(0, glyph.left - 2);
  final bottom = math.min(rows, glyph.bottom + 3);
  final right = math.min(cols, glyph.right + 3);
  final inked = <double>[
    for (var y = top; y < bottom; y++)
      for (var x = left; x < right; x++)
        if (diff[y * cols + x] > _inkStep) diff[y * cols + x],
  ]..sort();
  final peak = inked[(0.95 * (inked.length - 1)).toInt()];
  final cut = math.max(_inkStep.toDouble(), 0.4 * peak);
  var t = bottom;
  var l = right;
  var b = top - 1;
  var r = left - 1;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      if (diff[y * cols + x] > cut) {
        t = math.min(t, y);
        b = math.max(b, y);
        l = math.min(l, x);
        r = math.max(r, x);
      }
    }
  }
  final mask = Mask(b - t + 1, r - l + 1);
  for (var y = t; y <= b; y++) {
    for (var x = l; x <= r; x++) {
      if (diff[y * cols + x] > cut) {
        mask.cells[(y - t) * mask.width + x - l] = 1;
      }
    }
  }
  return mask;
}

int? _digit(PencilNet net, Mask mask) {
  int? only;
  for (final frac in _fracs) {
    final p = net.probabilities(normalise(mask, frac));
    var best = 0;
    for (var i = 1; i < p.length; i++) {
      if (p[i] > p[best]) best = i;
    }
    if ((only != null && only != best) ||
        best == _notADigit ||
        p[best] < _sure) {
      return null;
    }
    only = best;
  }
  return only;
}

int? _read(
  PencilNet net,
  Float64List diff,
  int rows,
  int cols,
  List<Box> glyphs,
) {
  if (glyphs.isEmpty || glyphs.length > _maxDigits) return null;
  var number = 0;
  for (var i = 0; i < glyphs.length; i++) {
    final digit = _digit(net, _glyphMask(diff, rows, cols, glyphs[i]));
    if (digit == null || (i == 0 && digit == 0)) return null;
    number = number * 10 + digit;
  }
  return number;
}

List<(Box, List<Blob>)> _lone(List<Blob> found, double unit) {
  final grouped = patches(found, unit);
  final lone = <(Box, List<Blob>)>[];
  for (final (box, strokes) in grouped) {
    final mates = grouped.any(
      (o) =>
          !identical(o.$1, box) &&
          box.sharesLine(o.$1) &&
          box.joins(o.$1, _mateReach * unit),
    );
    final sized =
        _heightLow * unit <= box.height &&
        box.height <= _heightHigh * unit &&
        box.width <= _maxWidth * box.height;
    if (sized && !mates) lone.add((box, strokes));
  }
  return lone.length <= _maxPatches ? lone : const [];
}

bool _pencil(Float64List diff, int cols, List<Blob> strokes) {
  var peak = 0.0;
  var dark = 0;
  var all = 0;
  for (final s in strokes) {
    for (var i = 0; i < s.ys.length; i++) {
      final v = diff[s.ys[i] * cols + s.xs[i]];
      peak = math.max(peak, v);
      if (v > _print) dark++;
      all++;
    }
  }
  return peak >= _minPeak && dark / all <= _printShare;
}

/// The pencilled page number in the margin of the upright [gray] page
/// ([width] x [height]), or null. [body] is the text's box (left, top, right,
/// bottom) in its pixels and [line] the text-line height in pixels.
int? findPencilNumber(
  PencilNet net,
  Uint8List gray,
  int width,
  int height,
  ({int left, int top, int right, int bottom}) body,
  double line,
) {
  final factor = math.max(1, (line / _unitPx).floor());
  final unit = line / factor;
  final (small, rows, cols) = shrink(gray, width, height, factor);
  final paper = paperMap(small, rows, cols, nearest(_blur * unit));
  final diff = Float64List(rows * cols);
  final ink = Uint8List(rows * cols);
  for (var i = 0; i < diff.length; i++) {
    diff[i] = paper[i] - small[i];
    ink[i] = diff[i] > _inkStep ? 1 : 0;
  }
  final left = body.left ~/ factor;
  final top = body.top ~/ factor;
  final right = body.right ~/ factor;
  final bottom = body.bottom ~/ factor;
  final bodyPixels = <int>[
    for (var y = top; y < bottom; y++)
      for (var x = left; x < right; x++) small[y * cols + x],
  ];
  final paperLevel = median(bodyPixels);
  final pad = nearest(unit);
  final columns = (math.max(0, left - pad), math.min(cols, right + pad));
  final numbers = <int>{};
  for (final span in [(0, top), (bottom, rows)]) {
    if (span.$2 - span.$1 < unit) continue;
    final region = (
      top: span.$1,
      bottom: span.$2,
      left: columns.$1,
      right: columns.$2,
    );
    for (final (box, strokes) in _lone(
      blobs(ink, cols, region, unit, _busy),
      unit,
    )) {
      final around = <int>[
        for (
          var y = math.max(0, box.top - pad);
          y < math.min(rows, box.bottom + pad + 1);
          y++
        )
          for (
            var x = math.max(0, box.left - pad);
            x < math.min(cols, box.right + pad + 1);
            x++
          )
            small[y * cols + x],
      ];
      if (median(around) < _paperShare * paperLevel ||
          !_pencil(diff, cols, strokes)) {
        continue;
      }
      final number = _read(net, diff, rows, cols, mergeGlyphs(strokes));
      if (number != null) numbers.add(number);
    }
  }
  return numbers.length == 1 ? numbers.first : null;
}
