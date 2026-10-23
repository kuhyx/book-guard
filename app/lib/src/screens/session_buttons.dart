import 'package:book_guard_app/src/capture.dart';
import 'package:book_guard_app/src/guard_state.dart';
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
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        FilledButton.icon(
          onPressed: photo == null
              ? null
              : () => photo(reading == null ? 'start' : 'stop'),
          icon: Icon(desktop ? Icons.upload_file : Icons.photo_camera),
          label: Text(reading == null ? 'Start reading' : 'Stop reading'),
        ),
        for (final c in captures)
          FilledButton.tonalIcon(
            onPressed: resume == null ? null : () => resume(c),
            icon: const Icon(Icons.restore),
            label: Text(
              'Finish the ${c.label} photo from '
              '${_clock(c.takenAt.toLocal())}',
            ),
          ),
        for (final s in checks)
          FilledButton.tonalIcon(
            onPressed: photo == null
                ? null
                : () => photo('check${s.checkPage}'),
            icon: const Icon(Icons.fact_check),
            label: Text('Photograph page ${s.checkPage}'),
          ),
      ],
    );
  }
}
