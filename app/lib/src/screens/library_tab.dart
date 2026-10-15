import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// `D.M.YYYY`, local.
String dmy(DateTime? moment) {
  if (moment == null) return '-';
  final local = moment.toLocal();
  return '${local.day}.${local.month}.${local.year}';
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

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  /// The kept copy at once (offline-first), then the PC's.
  Future<void> _start() async {
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

  Future<void> _load() async {
    final library = await widget.api.loadLibrary();
    if (!mounted) return;
    setState(() {
      _library = library;
      _loaded = true;
    });
  }

  String _subtitle(LibraryBook book) {
    final pages = '${book.lastPageRead ?? 0}/${book.pages ?? '?'}';
    final when = switch (book.status) {
      'finished' => 'finished ${dmy(book.finishedAt)}',
      'reading' => '${dmy(book.firstReadAt)} - ${dmy(book.lastReadAt)}',
      _ => 'not started',
    };
    return [
      if (book.author.isNotEmpty) book.author,
      'p. $pages - $when',
      '${book.sessions.length} sessions, ${book.notes.length} notes',
    ].join('\n');
  }

  void _open(LibraryBook book) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LibraryBookScreen(api: widget.api, book: book),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final books = _library?.books ?? const <LibraryBook>[];
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (books.isEmpty)
            const EmptyState(
              icon: Icons.local_library_outlined,
              title: 'No books yet',
              message: 'The PC lists every registered book here.',
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
                ),
                title: Text(book.title),
                subtitle: Text(_subtitle(book)),
                onTap: () => _open(book),
              ),
            ),
        ],
      ),
    );
  }
}
