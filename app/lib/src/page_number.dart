/// The printed page number, as the phone reads it -- the same rules as the
/// PC's `book_guard/_pagenum.py`, so both sides agree on what a photo shows.
///
/// A page number is a line holding nothing but 1-4 digits in the top or
/// bottom fifth of the upright page. What the photo is *for* chooses among
/// several (a chapter-opening page also has a chapter numeral); two left
/// standing is "unclear", never a pick.
library;

import 'dart:math' as math;

/// left, top, right, bottom.
typedef Box = ({int left, int top, int right, int bottom});

/// One recognised line, in the pixels of the image it was read from.
class SeenLine {
  /// Creates a line.
  const new(this.text, this.box, {this.words = const []});

  /// The line's text.
  final String text;

  /// Where it is.
  final Box box;

  /// Its words with their boxes (for telling upright from sideways).
  final List<(String, Box)> words;
}

/// A candidate page number and where it is printed (stored pixels).
class NumberHit {
  /// Creates a hit.
  const new(this.value, this.box);

  /// The number.
  final int value;

  /// Where it is printed, in the stored file's pixels (before EXIF).
  final Box box;
}

/// What a photo was taken for, as far as its page number goes.
class PageContext {
  /// Creates a context.
  const new({this.expected, this.after, this.near, this.lastPage});

  /// A check photo: the page that was asked for.
  final int? expected;

  /// A stop photo: the open session's start page.
  final int? after;

  /// A start photo: where the last session ended.
  final int? near;

  /// The book's last page.
  final int? lastPage;
}

/// The page number chosen, or why there is none.
class PageChoice {
  /// Creates a choice.
  const new(this.hit, [this.reason = '']);

  /// The chosen number, or null.
  final NumberHit? hit;

  /// Why nothing was chosen.
  final String reason;
}

final _number = RegExp(r'^\d{1,4}$');
const _edgeBand = 0.2;
const _anyPage = 9999;

/// A start further than this from the last session's end is not taken on
/// the reader's own say-so (`FAR_FROM_LAST` on the PC).
const farFromLast = 20;

/// Lines that are a lone number near the top or bottom of an image
/// [height] pixels tall.
List<SeenLine> numberLines(List<SeenLine> lines, int height) => [
  for (final line in lines)
    if (_number.hasMatch(line.text.trim()) &&
        math.min(_middle(line.box), height - _middle(line.box)) <=
            height * _edgeBand)
      line,
];

double _middle(Box box) => (box.top + box.bottom) / 2;

/// Confident real words laid out horizontally: high only when upright.
/// A sideways page's words come out taller than wide.
int wideWords(List<SeenLine> lines) {
  var count = 0;
  for (final line in lines) {
    for (final (text, box) in line.words) {
      final wide = box.right - box.left > 1.5 * (box.bottom - box.top);
      if (text.length >= 3 &&
          RegExp(r'^\p{L}+$', unicode: true).hasMatch(text) &&
          wide) {
        count++;
      }
    }
  }
  return count;
}

/// The hit among [hits] that fits [context] -- or why none does.
PageChoice choosePage(
  List<NumberHit> hits,
  PageContext context, {
  bool boxed = false,
}) {
  final expected = context.expected;
  if (expected != null) {
    for (final hit in hits) {
      if (hit.value == expected) return PageChoice(hit);
    }
    return PageChoice(null, 'page $expected not found on the photo');
  }
  final top = context.lastPage ?? _anyPage;
  final seen = <int>{};
  final options = [
    for (final hit in hits)
      if (hit.value >= 1 &&
          hit.value <= top &&
          (context.after == null || hit.value > context.after!) &&
          seen.add(hit.value))
        hit,
  ];
  if (options.isEmpty) {
    return PageChoice(
      null,
      context.after != null && hits.isNotEmpty
          ? 'no page after ${context.after} found on the photo'
          : 'no page number found',
    );
  }
  final near = context.near;
  if (options.length == 1) {
    final only = options.single;
    if (!boxed &&
        near != null &&
        context.after == null &&
        (only.value - near).abs() > farFromLast) {
      return PageChoice(
        null,
        'page ${only.value} is far from p. $near, the last one',
      );
    }
    return PageChoice(only);
  }
  if (near != null && context.after == null) {
    final ranked = [
      ...options,
    ]..sort((a, b) => (a.value - near).abs().compareTo((b.value - near).abs()));
    if ((ranked[0].value - near).abs() < (ranked[1].value - near).abs()) {
      return PageChoice(ranked[0]);
    }
  }
  return PageChoice(
    null,
    'page number unclear (${options.map((h) => h.value).join(' or ')})',
  );
}

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
