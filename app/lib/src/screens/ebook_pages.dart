import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Where each screen of [text] starts: paragraph boundaries, at least
/// [target] characters apart (a paragraph longer than two screens is cut at
/// a space). A screen is the reader's unit of position, so a position is
/// exact and restoring it needs no scroll arithmetic.
List<int> screenStarts(String text, int target) {
  final starts = [0];
  var from = 0;
  while (from + target < text.length) {
    final para = text.indexOf('\n\n', from + target);
    final next = para < 0 ? text.length : para + 2;
    if (next - from <= 2 * target) {
      if (next >= text.length) break;
      starts.add(next);
      from = next;
      continue;
    }
    final space = text.lastIndexOf(' ', from + target);
    from = space > from ? space + 1 : from + target;
    starts.add(from);
  }
  return starts;
}

/// The longest wall-clock span a session may have (`MAX_SESSION` on the PC).
const maxSession = Duration(hours: 6);

/// Under this per page, the PC counts the session as flipped through.
const minSecondsPerPage = 50;

/// Asks [text]: true for [yes], false for [no], null when dismissed.
Future<bool?> askYesNo(
  BuildContext context,
  String text,
  String yes,
  String no,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    content: Text(text),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(no),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(yes),
      ),
    ],
  ),
);

/// One screen of the book: its paragraphs, scrollable within the screen.
class EbookScreenText extends StatelessWidget {
  /// Creates the screen for `text[from, to)`.
  const new({
    required this.text,
    required this.from,
    required this.to,
    required this.fontSize,
    super.key,
  });

  /// The whole book.
  final String text;

  /// Where the screen starts.
  final int from;

  /// Where the next one starts.
  final int to;

  /// The reader's font size.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final paragraphs = text
        .substring(from, to)
        .split('\n\n')
        .where((p) => p.trim().isNotEmpty);
    final style = TextStyle(fontSize: fontSize, height: 1.5);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(p.trim(), style: style),
            ),
        ],
      ),
    );
  }
}
