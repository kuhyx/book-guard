/// Glyph helpers shared by the book screens: a failure cue whose words go
/// to the error log, a number beside its icon, an outline illustration for
/// an empty list, and a session's page range as numerals.
library;

import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/session_info.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// A failure no reply code names (an exception): the error glyph.
const failedCue = Cue(CueKind.error, semanticLabel: 'Something went wrong');

/// Shows [failedCue] (or [cue]) and keeps what went wrong in the error log:
/// the reason is for a later reader of the log, never painted.
void reportFailure(
  BuildContext context,
  GuardApi api,
  String stage,
  Object error, {
  Cue cue = failedCue,
}) {
  showCue(context, cue);
  unawaited(api.errors.log(stage, '$error'));
}

/// A session's pages as numerals, `40-52`, with a leading `≈` when the
/// pages are an estimate.
String pageSpan(SessionInfo session) =>
    '${session.estimated ? '≈' : ''}${session.startPage}-${session.endPage}';

/// An icon followed by a number (or any content); the icon's spoken label
/// names what the number counts.
class IconNumber extends StatelessWidget {
  /// Creates the pair; [color] tints the glyph.
  const new(
    this.icon,
    this.value, {
    required this.semanticLabel,
    this.color,
    super.key,
  });

  /// The glyph.
  final IconData icon;

  /// The number shown beside it.
  final String value;

  /// Spoken name of what [value] counts; never painted.
  final String semanticLabel;

  /// Glyph tint; the theme's when null.
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color, semanticLabel: semanticLabel),
      const SizedBox(width: AppSpacing.xs),
      Flexible(child: Text(value)),
    ],
  );
}

/// A 64 px outline illustration instead of an empty-list sentence.
class EmptyGlyph extends StatelessWidget {
  /// Creates the illustration of [icon].
  const new(this.icon, {required this.semanticLabel, super.key});

  /// The outline glyph.
  final IconData icon;

  /// Spoken description; never painted.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Center(
      child: Icon(
        icon,
        size: 64,
        semanticLabel: semanticLabel,
        color: Theme.of(context).colorScheme.outline,
      ),
    ),
  );
}

/// The glyph and tint for a library book's status (`finished`, `reading`,
/// anything else = not started).
IconData bookStatusIcon(String status) => switch (status) {
  'finished' => Icons.check_circle,
  'reading' => Icons.timelapse,
  _ => Icons.hourglass_empty,
};

/// The tint for [bookStatusIcon].
Color bookStatusTint(BuildContext context, String status) => switch (status) {
  'finished' => context.statusColors.success,
  'reading' => context.statusColors.warning,
  _ => Theme.of(context).colorScheme.onSurfaceVariant,
};
