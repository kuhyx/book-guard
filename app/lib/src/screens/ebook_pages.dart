import 'package:book_guard_app/src/screens/ebook_fit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

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

/// One screen of the book: `text[from, to)` set exactly as [fit] measured
/// it, so it never runs past the screen and never scrolls inside it.
class EbookScreenText extends StatelessWidget {
  /// Creates the screen for `text[from, to)`.
  const new({
    required this.text,
    required this.from,
    required this.to,
    required this.fit,
    super.key,
  });

  /// The whole book.
  final String text;

  /// The screen's first visible character.
  final int from;

  /// Where the next screen starts.
  final int to;

  /// The style, scaler and box the screen was measured with.
  final ScreenFit fit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Align(
      alignment: Alignment.topLeft,
      child: Text(
        // A trailing paragraph break would add a line never measured.
        text.substring(from, to).trimRight(),
        style: fit.style,
        textScaler: fit.scaler,
        textHeightBehavior: fit.heightBehavior,
      ),
    ),
  );
}
