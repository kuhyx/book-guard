import 'dart:async';

import 'package:book_guard_app/src/library.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for a note's text, and optionally its page and chapter (one chip
/// per chapter; tap the chosen one again for none); returns the note to
/// save, or null if cancelled. [existing] is edited in place
/// (same id); otherwise a new note gets [newId].
Future<Note?> editNote(
  BuildContext context, {
  required LibraryBook book,
  required String Function() newId,
  Note? existing,
}) => showDialog<Note>(
  context: context,
  builder: (_) => _NoteDialog(book: book, newId: newId, existing: existing),
);

class _NoteDialog extends StatefulWidget {
  const new({required this.book, required this.newId, this.existing});

  final LibraryBook book;
  final String Function() newId;
  final Note? existing;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _text = TextEditingController(text: widget.existing?.text);
  late final _page = TextEditingController(
    text: widget.existing?.page?.toString(),
  );
  late String _chapter = widget.existing?.chapter ?? '';

  /// A save was tried with no text: the field is red until it is typed in.
  bool _empty = false;

  @override
  void dispose() {
    _text.dispose();
    _page.dispose();
    super.dispose();
  }

  void _save() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      // Notes are never deleted: no empty save.
      setState(() => _empty = true);
      unawaited(HapticFeedback.heavyImpact());
      return;
    }
    final now = DateTime.now();
    final old = widget.existing;
    Navigator.of(context).pop(
      Note(
        id: old?.id ?? widget.newId(),
        isbn: widget.book.isbn,
        text: text,
        page: int.tryParse(_page.text.trim()),
        chapter: _chapter,
        createdAt: old?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapters = [for (final c in widget.book.chapters) c.title];
    if (_chapter.isNotEmpty && !chapters.contains(_chapter)) {
      chapters.add(_chapter);
    }
    return AlertDialog(
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconField(
              icon: Icons.edit_note,
              semanticLabel: 'Note',
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 10,
              errorBorder: _empty,
              onChanged: (_) {
                if (_empty) setState(() => _empty = false);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            IconField(
              icon: Icons.bookmark_border,
              semanticLabel: 'Page (optional)',
              controller: _page,
              keyboardType: TextInputType.number,
            ),
            if (chapters.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.list, semanticLabel: 'Chapter'),
                  for (final c in chapters)
                    ChoiceChip(
                      label: Text(c),
                      selected: c == _chapter,
                      onSelected: (on) =>
                          setState(() => _chapter = on ? c : ''),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
        ),
        IconButton.filled(
          onPressed: _save,
          icon: const Icon(Icons.check, semanticLabel: 'Save'),
        ),
      ],
    );
  }
}
