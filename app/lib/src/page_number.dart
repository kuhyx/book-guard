/// The printed page number, as the phone reads it -- the same rules as the
/// PC's `book_guard/_pagenum.py`, so both sides agree on what a photo shows.
///
/// A page number is a line holding nothing but 1-4 digits in the top or
/// bottom fifth of the upright page. What the photo is *for* chooses among
/// several (a chapter-opening page also has a chapter numeral); two left
/// standing is "unclear", never a pick.
library;

import 'dart:math' as math;

export 'package:book_guard_app/src/page_box.dart';

/// left, top, right, bottom.
typedef Box = ({int left, int top, int right, int bottom});

/// One recognised line, in the pixels of the image it was read from.
class SeenLine {
  /// Creates a line.
  const new(
    this.text,
    this.box, {
    this.words = const [],
    this.confidence = const [],
    this.angle,
  });

  /// The line's text.
  final String text;

  /// Where it is.
  final Box box;

  /// Its words with their boxes (for telling upright from sideways).
  final List<(String, Box)> words;

  /// ML Kit's confidence (0-1) per word, aligned with [words]; null or
  /// missing where it gives none.
  final List<double?> confidence;

  /// Degrees ML Kit turned the line to read it; null if it does not say.
  final double? angle;
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

final _ends = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true);
final _alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);
const _sure = 0.6;
const _upright = 45;

/// The number a line holds once ornaments are set aside -- or null.
///
/// Swashes or dashes either side of a page number ("~ 9 ~", p. 9 of
/// 2026-10-30) come out as symbols or unsure letters: those words do not
/// count. A real word beside a number ("s. 18") still disqualifies it, as
/// does an unsure number (`_MIN_CONF` on the PC).
int? loneNumber(SeenLine line) {
  final words = line.words.isEmpty
      ? [(line.text, 1.0)]
      : [
          for (final (i, (text, _)) in line.words.indexed)
            (text, i < line.confidence.length ? line.confidence[i] : null),
        ];
  final kept = [
    for (final (text, conf) in words)
      if (_alnum.hasMatch(text) && (conf ?? 1) >= _sure)
        text.replaceAll(_ends, ''),
  ];
  return kept.length == 1 && _number.hasMatch(kept.single)
      ? int.parse(kept.single)
      : null;
}

/// Lone numbers near the top or bottom of an image [height] pixels tall,
/// with their lines. Lines of nothing but the number come first, as on the
/// PC; only when there are none are ornaments set aside ([loneNumber]), so
/// a page that read before reads exactly as before.
List<(int, SeenLine)> numberLines(List<SeenLine> lines, int height) {
  final edge = [
    for (final line in lines)
      if (math.min(_middle(line.box), height - _middle(line.box)) <=
          height * _edgeBand)
        line,
  ];
  final bare = [
    for (final line in edge)
      if (_number.hasMatch(line.text.trim()))
        (int.parse(line.text.trim()), line),
  ];
  return bare.isNotEmpty
      ? bare
      : [
          for (final line in edge)
            if (loneNumber(line) case final number?) (number, line),
        ];
}

/// The number in a boxed crop, already turned upright -- or null.
///
/// A line ML Kit had to turn to read is a glyph read the wrong way up: a
/// flipped "9" reads "6" (the "page 6" box of 2026-10-30 was a 9).
int? boxNumber(List<SeenLine> lines) {
  for (final line in lines) {
    final turned = (line.angle ?? 0) % 360; // (-180, 180] or [0, 360)
    if (math.min(turned, 360 - turned) > _upright) continue;
    final digits = line.text
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll(_ends, '');
    if (_number.hasMatch(digits)) return int.parse(digits);
  }
  return null;
}

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
