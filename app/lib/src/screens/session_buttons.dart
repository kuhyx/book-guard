import 'package:book_guard_app/src/capture.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/photo_mark.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The Read tab's photo buttons: start or stop, finish a photo stored and
/// never sent, and one per check page the PC asks for.
class SessionButtons extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.reading,
    required this.desktop,
    required this.captures,
    required this.checks,
    required this.onPhoto,
    required this.onResume,
    super.key,
  });

  /// The page reading started at, or null when not reading.
  final int? reading;

  /// Desktop: a file instead of the camera.
  final bool desktop;

  /// Photos back from the camera that were never sent.
  final List<Capture> captures;

  /// Sessions whose check page is still to be photographed.
  final List<SessionInfo> checks;

  /// Takes a photo for a label (`start`, `stop`, `check<N>`); null while
  /// busy.
  final void Function(String label)? onPhoto;

  /// Finishes a stored photo; null while busy.
  final void Function(Capture capture)? onResume;

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final (photo, resume) = (onPhoto, onResume);
    final since = reading;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        // Camera (file on the desktop) + play to start; + stop and the page
        // reading began at to stop.
        GlyphButton(
          filled: true,
          icon: desktop ? Icons.upload_file : Icons.photo_camera,
          semanticLabel: since == null ? 'Start reading' : 'Stop reading',
          onPressed: photo == null
              ? null
              : () => photo(since == null ? 'start' : 'stop'),
          badge: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(since == null ? Icons.play_arrow : Icons.stop),
              if (since != null) Text('$since'),
            ],
          ),
        ),
        for (final c in captures)
          GlyphButton(
            icon: Icons.restore,
            semanticLabel: 'Finish the stored photo',
            onPressed: resume == null ? null : () => resume(c),
            badge: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LabelMark(c.label),
                const SizedBox(width: AppSpacing.sm),
                Text(_clock(c.takenAt.toLocal())),
              ],
            ),
          ),
        for (final s in checks)
          GlyphButton(
            icon: Icons.fact_check,
            semanticLabel: 'Photograph the check page',
            onPressed: photo == null
                ? null
                : () => photo('check${s.checkPage}'),
            badge: Text('${s.checkPage}'),
          ),
      ],
    );
  }
}
