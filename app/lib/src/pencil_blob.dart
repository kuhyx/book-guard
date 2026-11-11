/// Strokes of ink in a margin, joined into patches and glyphs: the geometry
/// under `pencil_find.dart` (port of `book_guard/_pencil_blob.py` and the
/// box helpers of `_patch.py`).
library;

import 'dart:typed_data';

const _minArea = 0.03;
const _minSide = 0.2;
const _maxSide = 6.0;
const _join = 1.0;
const _overlap = 0.5;

/// A box of pixels, inclusive on every side.
class Box {
  /// Creates a box.
  const new(this.left, this.top, this.right, this.bottom);

  /// Left column.
  final int left;

  /// Top row.
  final int top;

  /// Right column.
  final int right;

  /// Bottom row.
  final int bottom;

  /// Rows covered.
  int get height => bottom - top + 1;

  /// Columns covered.
  int get width => right - left + 1;

  /// Whether the boxes lie within [gap] of each other.
  bool joins(Box o, double gap) =>
      left - gap <= o.right &&
      o.left - gap <= right &&
      top - gap <= o.bottom &&
      o.top - gap <= bottom;

  /// The smallest box holding both.
  Box merged(Box o) => Box(
    left < o.left ? left : o.left,
    top < o.top ? top : o.top,
    right > o.right ? right : o.right,
    bottom > o.bottom ? bottom : o.bottom,
  );

  /// Whether the vertical extents overlap by half the shorter box.
  bool sharesLine(Box o) {
    final lo = top > o.top ? top : o.top;
    final hi = bottom < o.bottom ? bottom : o.bottom;
    final shorter = height < o.height ? height : o.height;
    return (hi - lo + 1) * 2 >= shorter;
  }
}

/// One 8-connected run of ink: its box and its pixels (whole image's coords).
class Blob {
  /// Creates a blob.
  const new(this.box, this.ys, this.xs);

  /// The run's box.
  final Box box;

  /// Row of each pixel.
  final List<int> ys;

  /// Column of each pixel.
  final List<int> xs;
}

/// Glyph-sized runs of ink in [region] (top, bottom, left, right) of [ink]
/// (row-major, [width] wide). A run touching the region's edge, dust or too
/// big is dropped, and so is the whole region when more than [busy] of it is
/// ink.
List<Blob> blobs(
  Uint8List ink,
  int width,
  ({int top, int bottom, int left, int right}) region,
  double unit,
  double busy,
) {
  final h = region.bottom - region.top;
  final w = region.right - region.left;
  if (h <= 0 || w <= 0) return const [];
  var count = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      count += ink[(region.top + y) * width + region.left + x];
    }
  }
  if (count / (h * w) > busy) return const [];
  final seen = Uint8List(h * w);
  final found = <Blob>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final at = y * w + x;
      if (seen[at] != 0 ||
          ink[(region.top + y) * width + region.left + x] == 0) {
        continue;
      }
      seen[at] = 1;
      final stack = <int>[at];
      final ys = <int>[];
      final xs = <int>[];
      var l = x;
      var t = y;
      var r = x;
      var b = y;
      while (stack.isNotEmpty) {
        final cell = stack.removeLast();
        final cy = cell ~/ w;
        final cx = cell % w;
        ys.add(cy);
        xs.add(cx);
        if (cx < l) l = cx;
        if (cx > r) r = cx;
        if (cy < t) t = cy;
        if (cy > b) b = cy;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final ny = cy + dy;
            final nx = cx + dx;
            if (ny < 0 || ny >= h || nx < 0 || nx >= w) continue;
            final n = ny * w + nx;
            if (seen[n] == 0 &&
                ink[(region.top + ny) * width + region.left + nx] != 0) {
              seen[n] = 1;
              stack.add(n);
            }
          }
        }
      }
      final big = (b - t + 1) > (r - l + 1) ? b - t + 1 : r - l + 1;
      final touches = l == 0 || t == 0 || r == w - 1 || b == h - 1;
      if (ys.length >= _minArea * unit * unit &&
          big >= _minSide * unit &&
          big <= _maxSide * unit &&
          !touches) {
        found.add(
          Blob(
            Box(
              l + region.left,
              t + region.top,
              r + region.left,
              b + region.top,
            ),
            [for (final v in ys) v + region.top],
            [for (final v in xs) v + region.left],
          ),
        );
      }
    }
  }
  return found;
}

/// Blobs within a text line of each other, joined (transitively): each
/// patch's box and its blobs.
List<(Box, List<Blob>)> patches(List<Blob> found, double unit) {
  final root = List<int>.generate(found.length, (i) => i);
  int find(int start) {
    var i = start;
    while (root[i] != i) {
      root[i] = root[root[i]];
      i = root[i];
    }
    return i;
  }

  for (var i = 0; i < found.length; i++) {
    for (var j = i + 1; j < found.length; j++) {
      if (found[i].box.joins(found[j].box, _join * unit)) {
        root[find(j)] = find(i);
      }
    }
  }
  final groups = <int, List<Blob>>{};
  for (var i = 0; i < found.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(found[i]);
  }
  return [
    for (final members in groups.values)
      (members.map((m) => m.box).reduce((a, b) => a.merged(b)), members),
  ];
}

/// Boxes of the glyphs in a patch, left to right: strokes whose columns
/// overlap are one glyph.
List<Box> mergeGlyphs(List<Blob> strokes) {
  final order = [for (var i = 0; i < strokes.length; i++) i]
    ..sort((a, b) {
      final c = strokes[a].box.left.compareTo(strokes[b].box.left);
      return c != 0 ? c : a.compareTo(b);
    });
  final glyphs = <Box>[];
  for (final i in order) {
    final box = strokes[i].box;
    var placed = false;
    for (var g = 0; g < glyphs.length; g++) {
      final glyph = glyphs[g];
      final lo = glyph.left > box.left ? glyph.left : box.left;
      final hi = glyph.right < box.right ? glyph.right : box.right;
      final narrower = glyph.width < box.width ? glyph.width : box.width;
      if (hi - lo + 1 >= _overlap * narrower) {
        glyphs[g] = glyph.merged(box);
        placed = true;
        break;
      }
    }
    if (!placed) glyphs.add(box);
  }
  final indexed = [for (var i = 0; i < glyphs.length; i++) i]
    ..sort((a, b) {
      final c = glyphs[a].left.compareTo(glyphs[b].left);
      return c != 0 ? c : a.compareTo(b);
    });
  return [for (final i in indexed) glyphs[i]];
}
