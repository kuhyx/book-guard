import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/screens/library_session_tile.dart';
import 'package:book_guard_app/src/screens/library_tab.dart';
import 'package:book_guard_app/src/screens/note_editor.dart';
import 'package:book_guard_app/src/screens/switch_book_button.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// One book from the library: chapters, every session with its full
/// summaries and the grader's replies and photos (from the PC's thumbs,
/// which outlive the phone's 40), and the notes, which can be added and
/// edited offline.
class LibraryBookScreen extends StatefulWidget {
  /// Creates the screen for [book].
  const new({
    required this.api,
    required this.book,
    this.state,
    this.onSwitched,
    super.key,
  });

  /// Where photos come from and notes go.
  final GuardApi api;

  /// The book as the library lists it.
  final LibraryBook book;

  /// The live snapshot: tells whether a session is open.
  final GuardState? state;

  /// Called with the ISBN once the switch is queued.
  final ValueChanged<String>? onSwitched;

  @override
  State<LibraryBookScreen> createState() => _LibraryBookScreenState();
}

class _LibraryBookScreenState extends State<LibraryBookScreen> {
  /// The notes written on this device (any book).
  List<Note> _device = const [];

  /// The book's notes as the PC's `library.json` has them, refreshed on
  /// load: a device note not in it (at that edit) shows as queued.
  late LibraryBook _pc = widget.book;

  @override
  void initState() {
    super.initState();
    unawaited(_loadNotes());
  }

  Future<void> _loadNotes() async {
    final device = await widget.api.deviceNotes();
    if (mounted) setState(() => _device = device);
    final library = await widget.api.loadLibrary();
    final fresh = library?.books
        .where((b) => b.isbn == widget.book.isbn)
        .firstOrNull;
    if (mounted && fresh != null) setState(() => _pc = fresh);
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
    if (mounted) {
      // Saved on the device; it reaches the PC when that is reachable.
      showReply(context, const GuardResponse(ok: true, code: 'note_saved'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final notes = mergeNotes(_pc, _device);
    return Scaffold(
      appBar: AppBar(title: Text(book.title)),
      floatingActionButton: FloatingActionButton(
        onPressed: _edit,
        child: const Icon(Icons.note_add_outlined, semanticLabel: 'Add a note'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (book.author.isNotEmpty) Text(book.author),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              IconNumber(
                Icons.last_page,
                '${book.lastPageRead ?? 0}/${book.pages ?? '?'}',
                semanticLabel: 'Pages',
              ),
              IconNumber(
                Icons.done_all,
                '${book.pagesRead}',
                semanticLabel: 'Pages credited',
              ),
              Icon(
                bookStatusIcon(book.status),
                color: bookStatusTint(context, book.status),
                semanticLabel: book.status,
              ),
              if (book.status == 'finished') Text(dmy(book.finishedAt)),
            ],
          ),
          SwitchBookButton(
            api: widget.api,
            book: book,
            state: widget.state,
            onSwitched: widget.onSwitched,
          ),
          _Section(Icons.sticky_note_2_outlined, 'Notes', [
            for (final note in notes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(note.text),
                subtitle: Wrap(
                  spacing: AppSpacing.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(dmy(note.updatedAt)),
                    if (note.page != null)
                      IconNumber(
                        Icons.bookmark_border,
                        '${note.page}',
                        semanticLabel: 'Page',
                      ),
                    if (note.chapter.isNotEmpty) Text(note.chapter),
                    if (queuedOnPhone(_pc, note))
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 18,
                        color: context.statusColors.warning,
                        semanticLabel: 'Queued: not on the PC yet',
                      ),
                  ],
                ),
                trailing: const Icon(
                  Icons.edit_outlined,
                  semanticLabel: 'Edit note',
                ),
                onTap: () => _edit(note),
              ),
          ]),
          _Section(Icons.list, 'Chapters', [
            for (final c in book.chapters)
              Row(
                children: [
                  SizedBox(width: 48, child: Text('${c.start}')),
                  Expanded(child: Text(c.title)),
                ],
              ),
          ]),
          _Section(Icons.history, 'Sessions', [
            for (final s in book.sessions.reversed)
              LibrarySessionTile(api: widget.api, session: s),
          ]),
        ],
      ),
    );
  }
}

/// A list under a small glyph in place of a heading; an empty one is a
/// 64 px outline of that glyph.
class _Section extends StatelessWidget {
  const new(this.icon, this.semanticLabel, this.items);

  final IconData icon;
  final String semanticLabel;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return EmptyGlyph(icon, semanticLabel: semanticLabel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Icon(
          icon,
          semanticLabel: semanticLabel,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: AppSpacing.xs),
        ...items,
      ],
    );
  }
}
