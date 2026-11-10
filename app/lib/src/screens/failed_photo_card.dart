import 'dart:typed_data';

import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:book_guard_app/src/screens/photo_mark.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// One failed photo: its thumbnail, a glyph for what went wrong, the number
/// the phone read (if any) and what can be done about it.
class FailedPhotoCard extends StatelessWidget {
  /// Creates the card for [failed].
  const new({
    required this.failed,
    required this.bytes,
    required this.reported,
    required this.onDismiss,
    super.key,
    this.onBox,
    this.onReport,
  });

  /// The photo and why it failed.
  final FailedPhoto failed;

  /// The device's copy of the photo, or null.
  final Uint8List? bytes;

  /// Whether a "this should not fail" report was already filed.
  final bool reported;

  /// Box the number; null hides the button.
  final VoidCallback? onBox;

  /// File a report; null disables the button.
  final VoidCallback? onReport;

  /// Hides the card on this device.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bytes = this.bytes;
    final page = failed.entry.page;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              height: 96,
              child: bytes == null
                  ? const Icon(
                      Icons.image_not_supported,
                      semanticLabel: 'photo gone',
                    )
                  : Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 144),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      LabelMark(failed.entry.label),
                      RejectBadge(failed.reason),
                      if (page != null) Text('$page'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (onBox case final onBox?)
                        GlyphButton(
                          icon: Icons.crop_free,
                          semanticLabel: 'Box the number',
                          onPressed: onBox,
                        ),
                      GlyphButton(
                        icon: reported ? Icons.flag : Icons.outlined_flag,
                        semanticLabel: reported
                            ? 'Reported'
                            : 'This should not fail',
                        onPressed: reported ? null : onReport,
                      ),
                      GlyphButton(
                        icon: Icons.close,
                        semanticLabel: 'Dismiss',
                        onPressed: onDismiss,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
