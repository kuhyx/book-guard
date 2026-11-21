import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for a page number on the dialog's own digit keypad; pops the
/// number, or null when cancelled or nothing was typed. Wordless: a number
/// glyph leads the field, the buttons are digits, delete, close and send.
///
/// The system keyboard is never asked for (`TextInputType.none`): on the
/// phone one refused a digit typed after a deleted pre-fill (234 -> 23, the
/// 7 never landed), so the keypad edits the field itself. A hardware
/// keyboard (the desktop build) still types into the field.
///
/// [initial] is a suggestion (a pencilled number the reader saw): it only
/// fills the field, and the number sent is whatever the field holds when the
/// reader taps send.
class TypePageDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({super.key, this.initial});

  /// The pre-fill, or null.
  final int? initial;

  @override
  State<TypePageDialog> createState() => _TypePageDialogState();
}

class _TypePageDialogState extends State<TypePageDialog> {
  late final _page = TextEditingController(text: widget.initial?.toString());

  /// Most digits a page number has.
  static const _maxDigits = 5;

  void _edit(String Function(String) change) {
    final text = change(_page.text);
    _page.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _digit(String d) => _edit((t) => t.length >= _maxDigits ? t : '$t$d');

  void _back() => _edit((t) => t.isEmpty ? t : t.substring(0, t.length - 1));

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
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconField(
          icon: Icons.pin,
          semanticLabel: 'The page number it has',
          controller: _page,
          keyboardType: TextInputType.none,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_maxDigits),
          ],
          autofocus: true,
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 12),
        _Keypad(onDigit: _digit, onBack: _back),
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
        semanticLabel: 'Send the typed page number',
        filled: true,
        onPressed: _send,
      ),
    ],
  );
}

/// Asks for the page number of the photo [name] and queues it for the PC,
/// which takes it as it takes the phone's own reading (`type_page`, so it
/// also works offline and from the desktop build); shows the reply. A sent
/// number that differs from [initial] carries it as `ocr_page`.
Future<void> typePage(
  BuildContext context,
  GuardApi api,
  String name, {
  int? initial,
}) async {
  final page = await showDialog<int>(
    context: context,
    builder: (_) => TypePageDialog(initial: initial),
  );
  if (page == null || !context.mounted) return;
  final response = await api.sendQueued('type_page', {
    'photo': name,
    'page': page,
    // A changed pre-fill is the reader's mistake: the PC files the photo.
    if (initial != null && initial != page) 'ocr_page': initial,
  });
  if (context.mounted) showReply(context, response);
}

/// Digits 1-9, then delete and 0: the dialog's own keypad.
class _Keypad extends StatelessWidget {
  const new({required this.onDigit, required this.onBack});

  final ValueChanged<String> onDigit;
  final VoidCallback onBack;

  // Keys share the dialog's width, never overflow a narrow screen.
  Widget _key(String id, Widget child, VoidCallback onTap) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: OutlinedButton(
        key: ValueKey('keypad-$id'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        child: child,
      ),
    ),
  );

  Widget _digit(String d) =>
      _key(d, Text(d, style: const TextStyle(fontSize: 22)), () => onDigit(d));

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Row(children: [for (final d in row) _digit(d)]),
      Row(
        children: [
          _key(
            'back',
            const Icon(
              Icons.backspace_outlined,
              semanticLabel: 'Delete the last digit',
            ),
            onBack,
          ),
          _digit('0'),
          // Keeps 0 under 8, as on a phone's keypad.
          const Spacer(),
        ],
      ),
    ],
  );
}
