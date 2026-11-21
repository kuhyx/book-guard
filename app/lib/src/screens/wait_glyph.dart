import 'package:material_ui/material_ui.dart';

/// Something is being checked and nothing is to be done: the stage's own
/// glyph (camera for a photo, pen for a summary) dimmed inside a spinner,
/// over a faint book. No button, no words; the stage is spoken only.
class WaitGlyph extends StatelessWidget {
  /// Creates the glyph for the stage [icon].
  const new(this.icon, {required this.semanticLabel, super.key});

  /// The stage's own action glyph.
  final IconData icon;

  /// What is being checked, for screen readers.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.auto_stories,
                size: 160,
                color: scheme.onSurface.withValues(alpha: 0.08),
              ),
              const SizedBox.square(
                dimension: 112,
                child: CircularProgressIndicator(strokeWidth: 4),
              ),
              Icon(
                icon,
                size: 48,
                color: scheme.onSurface.withValues(alpha: 0.38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
