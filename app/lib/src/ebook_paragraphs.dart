import 'package:flutter/foundation.dart';

/// What a paragraph of the book is, for setting it.
enum ParagraphKind {
  /// Running text.
  text,

  /// A heading: letters, none of them lowercase ("ROZDZIAŁ I").
  heading,

  /// A scene break: a short line with no letter or digit ("* * *").
  sceneBreak,
}

/// One paragraph: `text[start, end)`, trimmed, in the book's own offsets.
@immutable
class BookParagraph {
  /// Creates the paragraph.
  const new(this.start, this.end, this.kind, {required this.indented});

  /// Its first character in the book.
  final int start;

  /// One past its last visible character.
  final int end;

  /// How it is set.
  final ParagraphKind kind;

  /// Whether its first line is indented: running text, except the book's
  /// first paragraph and one right after a heading or a scene break.
  final bool indented;
}

/// The book split into paragraphs once, with each one's start offset into
/// the original text -- so a laid-out paragraph maps back to the exact
/// character the PC's page map counts.
class BookParagraphs {
  const new _(this.all);

  /// Splits [text] on blank lines (on single line breaks when it has no
  /// blank line at all).
  factory split(String text) {
    final gap = text.contains(_blankLine) ? _blankLine : _lineBreak;
    final all = <BookParagraph>[];
    var from = 0;
    void add(int to) {
      var (start, end) = (from, to);
      while (start < end && _isSpace(text.codeUnitAt(start))) {
        start++;
      }
      while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
        end--;
      }
      if (start == end) return;
      final kind = _kindOf(text.substring(start, end));
      final previous = all.isEmpty ? null : all.last.kind;
      all.add(
        BookParagraph(
          start,
          end,
          kind,
          indented:
              kind == ParagraphKind.text &&
              previous != null &&
              previous == ParagraphKind.text,
        ),
      );
    }

    for (final m in gap.allMatches(text)) {
      add(m.start);
      from = m.end;
    }
    add(text.length);
    return BookParagraphs._(List.unmodifiable(all));
  }

  /// The paragraphs, in order.
  final List<BookParagraph> all;

  /// How many there are.
  int get length => all.length;

  /// The paragraph [offset] is in, or the one before the gap it falls in;
  /// clamped to the first and last.
  int indexOf(int offset) {
    var (lo, hi) = (0, all.length - 1);
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (all[mid].start <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  static final _blankLine = RegExp(r'\n[^\S\n]*\n\s*');
  static final _lineBreak = RegExp(r'\n\s*');
  static final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _isSpace(int unit) =>
      unit == 0x20 || (unit >= 0x09 && unit <= 0x0d) || unit == 0xa0;

  static ParagraphKind _kindOf(String s) {
    if (!s.contains(_letterOrDigit)) {
      return s.length <= 20 ? ParagraphKind.sceneBreak : ParagraphKind.text;
    }
    final heading =
        s.length <= 80 && s.toUpperCase() == s && s.toLowerCase() != s;
    return heading ? ParagraphKind.heading : ParagraphKind.text;
  }
}
