import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// `DD.MM.YYYY`, local; `-` when there is no date.
String dmy(DateTime? moment) {
  if (moment == null) return '-';
  final local = moment.toLocal();
  final day = '${local.day}'.padLeft(2, '0');
  final month = '${local.month}'.padLeft(2, '0');
  return '$day.$month.${local.year}';
}

/// Every book ever read (book-guard `library.json`): finished or in
/// progress, its dates and pages; tap one for its chapters, sessions,
/// summaries, notes and photos. Shows the kept copy offline.
class LibraryTab extends StatefulWidget {
  /// Creates the tab.
  const new({required this.api, required this.state, super.key});

  /// The PC, through the share.
  final GuardApi api;

  /// The live snapshot: a newer one means the library may have changed.
  final GuardState? state;

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  Library? _library;
  bool _loaded = false;

  /// Notes written on this device: counted until the PC lists them.
  List<Note> _device = const [];

  /// The book just chosen with "Read this now", current here until the
  /// PC's library says so too.
  String? _chosen;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  /// The kept copy at once (offline-first), then the PC's.
  Future<void> _start() async {
    await _loadDeviceNotes();
    final kept = await widget.api.cachedLibrary();
    if (mounted && !_loaded && kept != null) {
      setState(() {
        _library = kept;
        _loaded = true;
      });
    }
    await _load();
  }

  @override
  void didUpdateWidget(LibraryTab old) {
    super.didUpdateWidget(old);
    if (old.state?.generatedAt != widget.state?.generatedAt) unawaited(_load());
  }

  Future<void> _loadDeviceNotes() async {
    final device = await widget.api.deviceNotes();
    if (mounted) setState(() => _device = device);
  }

  Future<void> _load() async {
    final library = await widget.api.loadLibrary();
    if (!mounted) return;
    setState(() {
      _library = library;
      _loaded = true;
      final agreed = library?.books.any((b) => b.current && b.isbn == _chosen);
      if (agreed ?? false) _chosen = null;
    });
  }

  /// [book] with the optimistic current flag applied.
  LibraryBook _shown(LibraryBook book) {
    final chosen = _chosen;
    return chosen == null
        ? book
        : book.withCurrent(current: book.isbn == chosen);
  }

  /// Opens [book]; on return counts the notes again (one may be new).
  Future<void> _open(LibraryBook book) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryBookScreen(
          api: widget.api,
          book: book,
          state: widget.state,
          onSwitched: (isbn) => setState(() => _chosen = isbn),
        ),
      ),
    );
    await _loadDeviceNotes();
  }

  @override
  Widget build(BuildContext context) {
    final books = [
      for (final b in _library?.books ?? const <LibraryBook>[]) _shown(b),
    ];
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (books.isEmpty)
            const EmptyGlyph(
              Icons.local_library_outlined,
              semanticLabel: 'No books yet',
            ),
          for (final book in books)
            Card(
              child: ListTile(
                isThreeLine: true,
                leading: Icon(
                  book.status == 'finished'
                      ? Icons.check_circle_outline
                      : book.current
                      ? Icons.auto_stories
                      : Icons.book_outlined,
                  semanticLabel: book.status,
                ),
                title: Text(book.title),
                subtitle: _Facts(book, notes: mergeNotes(book, _device).length),
                onTap: () => unawaited(_open(book)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A book's author, pages, dates and counts as numbers beside glyphs.
class _Facts extends StatelessWidget {
  const new(this.book, {required this.notes});

  final LibraryBook book;
  final int notes;

  @override
  Widget build(BuildContext context) {
    final finished = book.status == 'finished';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (book.author.isNotEmpty) Text(book.author),
        Wrap(
          spacing: AppSpacing.md,
          children: [
            IconNumber(
              Icons.last_page,
              '${book.lastPageRead ?? 0}/${book.pages ?? '?'}',
              semanticLabel: 'Pages',
            ),
            if (finished)
              IconNumber(
                Icons.check_circle,
                dmy(book.finishedAt),
                semanticLabel: 'Finished',
                color: context.statusColors.success,
              )
            else if (book.status == 'reading') ...[
              IconNumber(
                Icons.today,
                dmy(book.firstReadAt),
                semanticLabel: 'First read',
              ),
              IconNumber(
                Icons.event,
                dmy(book.lastReadAt),
                semanticLabel: 'Last read',
              ),
            ],
          ],
        ),
        Wrap(
          spacing: AppSpacing.md,
          children: [
            IconNumber(
              Icons.history,
              '${book.sessions.length}',
              semanticLabel: 'Sessions',
            ),
            IconNumber(
              Icons.sticky_note_2_outlined,
              '$notes',
              semanticLabel: 'Notes',
            ),
          ],
        ),
      ],
    );
  }
}
