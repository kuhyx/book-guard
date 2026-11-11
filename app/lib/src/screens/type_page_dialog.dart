import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for a page number on a numeric keypad; pops the number, or null
/// when cancelled or nothing was typed. Wordless: a number glyph leads the
/// field, the buttons are close and send.
class TypePageDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({super.key});

  @override
  State<TypePageDialog> createState() => _TypePageDialogState();
}

class _TypePageDialogState extends State<TypePageDialog> {
  final _page = TextEditingController();

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _send() {
    final page = int.tryParse(_page.text.trim());
    if (page != null) Navigator.of(context).pop(page);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: IconField(
      icon: Icons.pin,
      semanticLabel: 'The page number it has',
      controller: _page,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      autofocus: true,
      onSubmitted: (_) => _send(),
    ),
    actions: [
      GlyphButton(
        icon: Icons.close,
        semanticLabel: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      GlyphButton(
        icon: Icons.send,
        semanticLabel: 'Send the typed page number',
        filled: true,
        onPressed: _send,
      ),
    ],
  );
}

/// Asks for the page number of the photo [name] and queues it for the PC,
/// which takes it as it takes the phone's own reading (`type_page`, so it
/// also works offline and from the desktop build); shows the reply.
Future<void> typePage(BuildContext context, GuardApi api, String name) async {
  final page = await showDialog<int>(
    context: context,
    builder: (_) => const TypePageDialog(),
  );
  if (page == null || !context.mounted) return;
  final response = await api.sendQueued('type_page', {
    'photo': name,
    'page': page,
  });
  if (context.mounted) showReply(context, response);
}
