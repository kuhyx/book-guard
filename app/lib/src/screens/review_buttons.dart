import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/screens/review_result.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The review screen's buttons: retake (left), send without a number when
/// none was found, and the tick that sends the chosen number.
class ReviewButtons extends StatelessWidget {
  /// Creates the row for the number [hit] (null: none chosen yet);
  /// [reading] while a drawn box is being read.
  const new({required this.hit, required this.reading, super.key});

  /// The chosen number, if any.
  final NumberHit? hit;

  /// Whether a drawn box is being read.
  final bool reading;

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
          if (hit == null)
            GlyphButton(
              icon: Icons.send,
              semanticLabel: 'Send anyway',
              onPressed: () => Navigator.of(context).pop(const ReviewResult()),
            ),
          const SizedBox(width: AppSpacing.sm),
          GlyphButton(
            icon: Icons.check,
            semanticLabel: 'Send the page number',
            filled: true,
            badge: hit == null ? null : Text('${hit.value}'),
            onPressed: hit == null || reading
                ? null
                : () =>
                      Navigator.of(context)
                          .pop(ReviewResult(page: hit.value, box: hit.box)),
          ),
        ],
      ),
    );
  }
}
