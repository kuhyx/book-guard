import 'dart:math';

import 'package:flutter/widgets.dart';

/// The first character at or after [offset] that is not whitespace (the
/// text's length when only whitespace is left).
int firstVisible(String text, int offset) {
  var i = offset.clamp(0, text.length);
  while (i < text.length && text[i].trim().isEmpty) {
    i++;
  }
  return i;
}

/// [offset] moved on to the start of the next word, unless it already is
/// one: a screen never opens on half a word.
int wordAfter(String text, int offset) {
  var i = offset.clamp(0, text.length);
  if (i == 0 || text[i - 1].trim().isEmpty) return firstVisible(text, i);
  while (i < text.length && text[i].trim().isNotEmpty) {
    i++;
  }
  return firstVisible(text, i);
}

/// How text is set on one screen of the reader -- the exact style, scaler
/// and box the screen's `Text` is drawn with -- and so where a screen
/// starting at a given offset ends. Measured, never estimated: the next
/// screen starts on the first line that did not fit, so paging on skips
/// nothing and no screen is taller than the box.
@immutable
class ScreenFit {
  /// Creates the fit for a [size] text box.
  const new({
    required this.style,
    required this.scaler,
    required this.size,
    this.heightBehavior,
  });

  /// The fit for a screen of [box] less [pad] on each side, at [font] with
  /// line height 1.5 over the ambient style and the system font scale.
  factory of(
    BuildContext context,
    BoxConstraints box,
    double font,
    double pad,
  ) {
    final ambient = DefaultTextStyle.of(context);
    return ScreenFit(
      style: ambient.style.merge(TextStyle(fontSize: font, height: 1.5)),
      scaler: MediaQuery.textScalerOf(context),
      heightBehavior: ambient.textHeightBehavior,
      size: Size(box.maxWidth - 2 * pad, box.maxHeight - 2 * pad),
    );
  }

  /// The full text style the screen is drawn with.
  final TextStyle style;

  /// The system font scale.
  final TextScaler scaler;

  /// The box the text has, padding taken off.
  final Size size;

  /// The ambient text height behaviour, as `Text` uses it.
  final TextHeightBehavior? heightBehavior;

  /// The characters laid out first; doubled while they all fit.
  static const chunk = 4096;

  TextPainter _paint(String text) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    textHeightBehavior: heightBehavior,
  )..layout(maxWidth: size.width);

  /// Where the screen starting at [from] ends: the first visible character
  /// of the next one, or the text's length on the last screen.
  int endOf(String text, int from) {
    for (var size = chunk; ; size *= 2) {
      final stop = min(text.length, from + size);
      final painter = _paint(text.substring(from, stop));
      final lines = painter.computeLineMetrics();
      var bottom = 0.0;
      var fit = 0;
      while (fit < lines.length &&
          bottom + lines[fit].height <= this.size.height + 0.01) {
        bottom += lines[fit].height;
        fit++;
      }
      final whole = stop >= text.length;
      // The chunk's last line may hold a cut word, which can change where
      // the line before it breaks: only trust lines before those two.
      if (!whole && fit >= lines.length - 1) {
        painter.dispose();
        continue;
      }
      if (fit >= lines.length) {
        painter.dispose();
        return text.length;
      }
      if (fit == 0) bottom = lines.first.height; // a line taller than the box
      final next = painter.getPositionForOffset(Offset(0, bottom + 0.5));
      painter.dispose();
      return max(firstVisible(text, from + next.offset), from + 1);
    }
  }

  /// The earliest word start whose screen still reaches [to]: the screen
  /// before the one at [to], when there is no history to go back through.
  int startBefore(String text, int to) {
    for (var size = chunk; ; size *= 2) {
      final low = max(0, to - size);
      final starts = [
        for (var i = low; i < to; i++)
          if (text[i].trim().isNotEmpty &&
              (i == 0 || text[i - 1].trim().isEmpty))
            i,
      ];
      if (starts.isEmpty) return firstVisible(text, 0);
      if (low > 0 && endOf(text, starts.first) >= to) continue;
      var (lo, hi) = (0, starts.length - 1);
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (endOf(text, starts[mid]) >= to) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      return starts[lo];
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ScreenFit &&
      other.style == style &&
      other.scaler == scaler &&
      other.size == size &&
      other.heightBehavior == heightBehavior;

  @override
  int get hashCode => Object.hash(style, scaler, size, heightBehavior);
}
