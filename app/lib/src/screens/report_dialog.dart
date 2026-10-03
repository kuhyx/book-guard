import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Asks what the photo really shows; pops `(page, comment)` or null.
class ReportDialog extends StatefulWidget {
  /// Creates the dialog for a photo that failed with [reason].
  const new({required this.reason, super.key});

  /// What went wrong.
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
    title: const Text('This should not have failed'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('It failed with: ${widget.reason}'),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _page,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'The page number it shows',
          ),
        ),
        TextField(
          controller: _comment,
          decoration: const InputDecoration(labelText: 'Anything else'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.of(context)
                .pop((int.tryParse(_page.text.trim()), _comment.text.trim())),
        child: const Text('Send report'),
      ),
    ],
  );
}
