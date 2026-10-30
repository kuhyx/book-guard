import 'dart:ui' show BoxHeightStyle;

import 'package:book_guard_app/src/ebook_paragraphs.dart';
import 'package:book_guard_app/src/screens/ebook_words.dart';
import 'package:book_guard_app/src/screens/reading_style.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One paragraph of the book, set in [ReadingStyle] in a centred column.
///
/// An indented paragraph starts with a placeholder (a `WidgetSpan`), which
/// takes one code unit (U+FFFC) in the laid-out text: [ParagraphGeometry]
/// takes it off, so a position on screen maps to the book's own offset.
class ParagraphView extends StatelessWidget {
  /// Creates the view of [paragraph] of [text].
  const new({
    required this.text,
    required this.paragraph,
    required this.fontSize,
    required this.textKey,
    super.key,
  });

  /// The whole book.
  final String text;

  /// Which slice of it.
  final BookParagraph paragraph;

  /// The font size.
  final double fontSize;

  /// Finds the laid-out text again ([ParagraphGeometry]).
  final GlobalKey textKey;

  @override
  Widget build(BuildContext context) {
    final p = paragraph;
    final scene = p.kind == ParagraphKind.sceneBreak;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ReadingStyle.sideMargin,
        vertical: scene ? ReadingStyle.lineOf(fontSize) / 2 : 0,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints.tightFor(
            width: ReadingStyle.measure(fontSize),
          ),
          child: RichText(
            key: textKey,
            textAlign: scene ? TextAlign.center : TextAlign.start,
            // RichText's own default scaler is none: the size is the size.
            textHeightBehavior: ReadingStyle.heightBehavior,
            text: TextSpan(
              style: ReadingStyle.text(fontSize),
              children: [
                if (p.indented)
                  WidgetSpan(
                    child: SizedBox(width: ReadingStyle.indentEm * fontSize),
                  ),
                TextSpan(text: text.substring(p.start, p.end)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A laid-out paragraph, read back: which book character is at a height,
/// and how far down a book character's line starts.
class ParagraphGeometry {
  /// Pairs [_p] with its laid-out [box].
  const new(this._p, this.box);

  final BookParagraph _p;

  /// The laid-out text.
  final RenderParagraph box;

  int get _shift => _p.indented ? 1 : 0;

  /// A line cut by less than this is still read as whole.
  static const slack = 1.0;

  /// [local] (a laid-out offset, the placeholder counted) as a book offset.
  int _book(String text, int local) {
    final length = _p.end - _p.start;
    return firstVisible(text, _p.start + (local - _shift).clamp(0, length));
  }

  /// The line box (spacing above it included, so lines tile) of the
  /// laid-out character at [local]; null when it has none (a line break).
  Rect? _lineOf(int local) {
    final at = local.clamp(_shift, _shift + _p.end - _p.start - 1);
    final boxes = box.getBoxesForSelection(
      TextSelection(baseOffset: at, extentOffset: at + 1),
      boxHeightStyle: BoxHeightStyle.includeLineSpacingTop,
    );
    return boxes.isEmpty ? null : boxes.first.toRect();
  }

  /// The book offset of the line at [dy] (local to [box]), from its start.
  int offsetAt(String text, double dy) =>
      _book(text, box.getPositionForOffset(Offset(0, dy)).offset);

  /// The start of the first line whose top is at or below [dy]; null when
  /// the paragraph has none (the line at [dy] is its last, cut).
  int? firstWholeLine(String text, double dy) {
    if (dy <= slack) return firstVisible(text, _p.start);
    final local = box.getPositionForOffset(Offset(0, dy)).offset;
    final line = _lineOf(local);
    if (line == null || line.top >= dy - slack) return _book(text, local);
    final below = line.bottom + slack / 2;
    if (below >= box.size.height) return null;
    return offsetAt(text, below);
  }

  /// How far below [box]'s top the line holding book [offset] starts.
  double lineTop(int offset) {
    final local = offset - _p.start + _shift;
    if (local <= _shift) return 0;
    return _lineOf(local)?.top ?? 0;
  }
}
