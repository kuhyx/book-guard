import 'package:book_guard_app/src/library.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Asks for a note's text, and optionally its page and chapter; returns
/// the note to save, or null if cancelled. [existing] is edited in place
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

  @override
  void dispose() {
    _text.dispose();
    _page.dispose();
    super.dispose();
  }

  void _save() {
    final text = _text.text.trim();
    if (text.isEmpty) return; // Notes are never deleted: no empty save.
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
      title: Text(widget.existing == null ? 'New note' : 'Edit note'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 10,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _page,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Page (optional)'),
            ),
            if (chapters.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _chapter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Chapter'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('None')),
                  for (final c in chapters)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (value) => setState(() => _chapter = value ?? ''),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
