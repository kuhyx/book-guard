import 'package:material_ui/material_ui.dart';

/// The bar's bug glyph: copies the diagnostics, badged with the number of
/// uploads still waiting in the outbox.
class DiagnosticsButton extends StatelessWidget {
  /// Creates the button.
  const new({required this.waiting, required this.onPressed, super.key});

  /// Uploads still in the outbox; the badge hides at 0.
  final int waiting;

  /// Copies the diagnostics.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Diagnostics',
    icon: Badge(
      isLabelVisible: waiting > 0,
      label: Text('$waiting'),
      child: const Icon(
        Icons.bug_report_outlined,
        semanticLabel: 'copy diagnostics',
      ),
    ),
    onPressed: onPressed,
  );
}
