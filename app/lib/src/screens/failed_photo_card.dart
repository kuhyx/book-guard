import 'dart:typed_data';

import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// One failed photo: its thumbnail, what went wrong and what can be done.
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

  /// "Box the number"; null hides the button.
  final VoidCallback? onBox;

  /// "This should not fail"; null disables the button.
  final VoidCallback? onReport;

  /// Hides the card on this device.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bytes = this.bytes;
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
                  ? const Icon(Icons.image_not_supported)
                  : Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 144),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${failed.entry.label}: ${failed.reason}'),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      if (onBox case final onBox?)
                        TextButton(
                          onPressed: onBox,
                          child: const Text('Box the number'),
                        ),
                      TextButton(
                        onPressed: reported ? null : onReport,
                        child: Text(
                          reported ? 'Reported' : 'This should not fail',
                        ),
                      ),
                      TextButton(
                        onPressed: onDismiss,
                        child: const Text('Dismiss'),
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
