import 'package:book_guard_app/src/capture.dart';
import 'package:book_guard_app/src/next_step.dart';
import 'package:book_guard_app/src/screens/photo_mark.dart';
import 'package:book_guard_app/src/screens/wait_glyph.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The Read tab's one photo button for the [step] ([nextStep]): start or
/// stop, the check page, or finishing that step's photo stored and never
/// sent. A summary step has no photo button (the summary panel is the step).
class SessionButtons extends StatelessWidget {
  /// Creates the button.
  const new({
    required this.step,
    required this.busy,
    required this.reading,
    required this.desktop,
    required this.onPhoto,
    required this.onResume,
    super.key,
  });

  /// The one next step.
  final NextStep step;

  /// A photo is on its way: its glyph in a spinner instead of any button.
  final bool busy;

  /// The page reading started at, or null when not reading.
  final int? reading;

  /// Desktop: a file instead of the camera.
  final bool desktop;

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
    if (busy) {
      return const Center(
        child: WaitGlyph(
          Icons.photo_camera,
          semanticLabel: 'checking the photo',
        ),
      );
    }
    final label = step.label;
    if (label == null) return const SizedBox.shrink();
    if (step.capture case final c?) {
      return Align(
        alignment: Alignment.centerLeft,
        child: GlyphButton(
          filled: true,
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
      );
    }
    final onPressed = photo == null ? null : () => photo(label);
    final since = reading;
    return Align(
      alignment: Alignment.centerLeft,
      child: switch (step.kind) {
        StepKind.check => GlyphButton(
          filled: true,
          icon: Icons.fact_check,
          semanticLabel: 'Photograph the check page',
          onPressed: onPressed,
          badge: Text('${step.session?.checkPage}'),
        ),
        // Camera (file on the desktop) + play to start; + stop and the page
        // reading began at to stop.
        _ => GlyphButton(
          filled: true,
          icon: desktop ? Icons.upload_file : Icons.photo_camera,
          semanticLabel: step.kind == StepKind.start
              ? 'Start reading'
              : 'Stop reading',
          onPressed: onPressed,
          badge: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(step.kind == StepKind.start ? Icons.play_arrow : Icons.stop),
              if (step.kind == StepKind.stop && since != null) Text('$since'),
            ],
          ),
        ),
      },
    );
  }
}
