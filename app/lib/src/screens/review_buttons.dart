import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/screens/review_result.dart';
import 'package:book_guard_app/src/screens/type_page_dialog.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The review screen's buttons: retake (left), the keypad (always: a number
/// is never sent unless it was read or typed) and the tick that sends the
/// chosen number.
class ReviewButtons extends StatelessWidget {
  /// Creates the row for the number [hit] (null: none chosen yet);
  /// [reading] while a drawn box is being read.
  const new({
    required this.hit,
    required this.reading,
    required this.onType,
    required this.onSend,
    super.key,
  });

  /// The chosen number, if any.
  final NumberHit? hit;

  /// Whether a drawn box is being read.
  final bool reading;

  /// Opens the keypad.
  final VoidCallback onType;

  /// Sends the chosen number.
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final hit = this.hit;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          GlyphButton(
            icon: Icons.replay,
            semanticLabel: 'Retake',
            onPressed: () =>
                Navigator.of(context).pop(const ReviewResult(retake: true)),
          ),
          const Spacer(),
          GlyphButton(
            icon: Icons.dialpad,
            semanticLabel: 'Type the page number',
            onPressed: reading ? null : onType,
          ),
          const SizedBox(width: AppSpacing.sm),
          GlyphButton(
            icon: Icons.check,
            semanticLabel: 'Send the page number',
            filled: true,
            badge: hit == null ? null : Text('${hit.value}'),
            onPressed: hit == null || reading ? null : onSend,
          ),
        ],
      ),
    );
  }
}

/// The keypad of the review screen, pre-filled with the chosen number [hit]
/// (else a [pencil]led one). The result carries what the field holds, with
/// the box kept only when that is the number it surrounds; null when
/// cancelled.
Future<ReviewResult?> typeReview(
  BuildContext context, {
  required NumberHit? hit,
  required int? pencil,
  required int? ocr,
}) async {
  final page = await showDialog<int>(
    context: context,
    builder: (_) => TypePageDialog(initial: hit?.value ?? pencil),
  );
  if (page == null) return null;
  return ReviewResult(
    page: page,
    box: hit != null && hit.value == page ? hit.box : null,
    ocrPage: ocr,
  );
}
