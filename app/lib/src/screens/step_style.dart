import 'package:book_guard_app/src/next_step.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// One glyph and one colour per step (kuhy, 2026-11-24: start, stop and
/// the summary looked alike): a green play, a red stop, an amber pen. The
/// Read tab's badge and the Status tile of an owed summary use the same
/// pen in the same amber.
({IconData icon, Color color}) stepStyle(BuildContext context, StepKind kind) {
  final colors = context.statusColors;
  return switch (kind) {
    StepKind.start => (icon: Icons.play_arrow, color: colors.success),
    StepKind.stop => (icon: Icons.stop, color: colors.danger),
    StepKind.summary => (icon: Icons.edit, color: colors.warning),
  };
}

/// The step's main glyph on a filled button.
const double stepGlyphSize = 32;

/// The camera (or file) badge beside it.
const double stepBadgeSize = 16;
