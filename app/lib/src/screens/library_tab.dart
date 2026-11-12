import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/screens/fit_sheet.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:book_guard_app/src/screens/library_tiles.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

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
/// summaries, notes and photos. Shows the kept copy offline. Three columns
/// of text tiles fitted to the screen, paged sideways; a long-press shows
/// the author, dates and counts.
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
    if (books.isEmpty) {
      return const Center(
        child: EmptyGlyph(
          Icons.local_library_outlined,
          semanticLabel: 'No books yet',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: FitGrid(
        itemCount: books.length,
        itemBuilder: (context, i) {
          final book = books[i];
          return BookTile(
            book,
            onTap: () => unawaited(_open(book)),
            onLongPress: () => showFitSheet(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  BookFacts(book, notes: mergeNotes(book, _device).length),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
