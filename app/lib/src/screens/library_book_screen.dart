import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/screens/library_tab.dart';
import 'package:book_guard_app/src/screens/note_editor.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// One book from the library: chapters, every session with its full
/// summaries and the grader's replies and photos (from the PC's thumbs,
/// which outlive the phone's 40), and the notes, which can be added and
/// edited offline.
class LibraryBookScreen extends StatefulWidget {
  /// Creates the screen for [book].
  const new({required this.api, required this.book, super.key});

  /// Where photos come from and notes go.
  final GuardApi api;

  /// The book as the library lists it.
  final LibraryBook book;

  @override
  State<LibraryBookScreen> createState() => _LibraryBookScreenState();
}

class _LibraryBookScreenState extends State<LibraryBookScreen> {
  List<Note> _notes = const [];

  @override
  void initState() {
    super.initState();
    _notes = widget.book.notes;
    unawaited(_loadNotes());
  }

  Future<void> _loadNotes() async {
    final notes = await widget.api.notesOf(widget.book);
    if (mounted) setState(() => _notes = notes);
  }

  Future<void> _edit([Note? existing]) async {
    final note = await editNote(
      context,
      book: widget.book,
      newId: widget.api.newId,
      existing: existing,
    );
    if (note == null) return;
    await widget.api.saveNote(note);
    await _loadNotes();
    if (mounted) showToast(context, 'Note saved on the device.');
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return Scaffold(
      appBar: AppBar(title: Text(book.title)),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add a note',
        onPressed: _edit,
        child: const Icon(Icons.note_add_outlined),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (book.author.isNotEmpty) Text(book.author),
          Text(
            'p. ${book.lastPageRead ?? 0}/${book.pages ?? '?'} - '
            '${book.pagesRead} pages credited - '
            '${_status(book)}',
          ),
          const SectionHeader('Notes'),
          if (_notes.isEmpty) const Text('No notes yet.'),
          for (final note in _notes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(note.text),
              subtitle: Text(_place(note)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(note),
            ),
          const SectionHeader('Chapters'),
          if (book.chapters.isEmpty) const Text('No contents list.'),
          for (final c in book.chapters) Text('p. ${c.start}: ${c.title}'),
          const SectionHeader('Sessions'),
          if (book.sessions.isEmpty) const Text('No sessions yet.'),
          for (final s in book.sessions.reversed)
            _SessionTile(api: widget.api, session: s),
        ],
      ),
    );
  }

  static String _status(LibraryBook book) => switch (book.status) {
    'finished' => 'finished ${dmy(book.finishedAt)}',
    'reading' => 'in progress',
    _ => 'not started',
  };

  static String _place(Note note) => [
    dmy(note.updatedAt),
    if (note.page != null) 'p. ${note.page}',
    if (note.chapter.isNotEmpty) note.chapter,
  ].join(' - ');
}

class _SessionTile extends StatelessWidget {
  const new({required this.api, required this.session});

  final GuardApi api;
  final LibrarySession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final last = s.attempts.isEmpty ? null : s.attempts.last;
    final earlier = s.attempts.length > 1
        ? s.attempts.sublist(0, s.attempts.length - 1)
        : const <
            ({bool passed, String summary, String feedback, String grader})
          >[];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('${dmy(s.endedAt)} - p. ${s.startPage}-${s.endPage}'),
      subtitle: Text(
        '${s.pages ?? '?'} pages, ${s.minutes ?? '?'} min - ${s.status}',
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.photos.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final p in s.photos)
                InkWell(
                  onTap: () => openPhoto(context, api, p.file),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 72,
                        height: 96,
                        child: RemoteImage(
                          bytes: api.fetchBytes(p.thumb),
                          fit: BoxFit.cover,
                        ),
                      ),
                      Text('${p.role} p. ${p.page ?? '?'}'),
                    ],
                  ),
                ),
            ],
          ),
        const SectionHeader('Summary'),
        SelectableText(last?.summary ?? 'No summary written yet.'),
        if (last != null && last.feedback.isNotEmpty) ...[
          SectionHeader(
            'Grader${last.grader.isEmpty ? '' : ' (${last.grader})'}',
          ),
          SelectableText(last.feedback),
        ],
        for (final (i, a) in earlier.indexed)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Attempt ${i + 1} - ${a.passed ? 'passed' : 'failed'}'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [SelectableText(a.summary), SelectableText(a.feedback)],
          ),
      ],
    );
  }
}
