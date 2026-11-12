import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Asks what the photo really shows; pops `(page, comment)` or null.
/// Wordless: the failure is its glyph, the two fields are led by a number
/// and a pencil icon, the buttons are close and send.
class ReportDialog extends StatefulWidget {
  /// Creates the dialog for a photo that failed with [reason].
  const new({required this.reason, super.key});

  /// What went wrong (a reject glyph; never painted as text).
  final String reason;

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _page = TextEditingController();
  final _comment = TextEditingController();

  @override
  void dispose() {
    _page.dispose();
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: RejectBadge(widget.reason, size: 32),
        ),
        const SizedBox(height: AppSpacing.sm),
        IconField(
          icon: Icons.pin,
          semanticLabel: 'The page number it shows',
          controller: _page,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpacing.sm),
        IconField(
          icon: Icons.edit_note,
          semanticLabel: 'Anything else',
          controller: _comment,
        ),
      ],
    ),
    actions: [
      GlyphButton(
        icon: Icons.close,
        semanticLabel: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      GlyphButton(
        icon: Icons.send,
        semanticLabel: 'Send report',
        filled: true,
        onPressed: () =>
            Navigator.of(context)
                .pop((int.tryParse(_page.text.trim()), _comment.text.trim())),
      ),
    ],
  );
}
