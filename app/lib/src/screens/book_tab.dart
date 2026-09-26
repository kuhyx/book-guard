import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/open_library.dart';
import 'package:design_system/design_system.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Every ebook format the PC can extract text from (book-guard `_booktext`).
const ebookExtensions = <String>[
  'epub', 'kepub', 'mobi', 'azw', 'azw1', 'azw3', 'azw4', 'prc', 'pdb', //
  'fb2', 'fbz', 'lit', 'lrf', 'rb', 'snb', 'tcr', 'pml', 'chm', 'rtf', //
  'docx', 'odt', 'htmlz', 'txtz', 'pdf', 'djvu', 'djv', 'txt', 'md', //
  'html', 'htm', 'xhtml',
];

/// Picks a book file; replaced in tests.
typedef BookFileSource = Future<XFile?> Function();

Future<XFile?> _pickBook() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(label: 'Ebooks', extensions: ebookExtensions),
  ],
);

/// This month's book: find it by title, register it, attach its file.
class BookTab extends StatefulWidget {
  /// Creates the tab.
  const new({
    required this.api,
    required this.state,
    required this.onChanged,
    super.key,
    this.library,
    this.bookSource = _pickBook,
  });

  /// The PC.
  final GuardApi api;

  /// The latest snapshot.
  final GuardState? state;

  /// Refetch after an action.
  final Future<void> Function() onChanged;

  /// Title search; replaced in tests.
  final OpenLibrary? library;

  /// Where the book file comes from.
  final BookFileSource bookSource;

  @override
  State<BookTab> createState() => _BookTabState();
}

class _BookTabState extends State<BookTab> {
  final _query = TextEditingController();
  final _pages = TextEditingController();
  late final OpenLibrary _library = widget.library ?? OpenLibrary();
  List<BookHit> _hits = const [];
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (error) {
      if (mounted) showError(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(widget.onChanged());
    }
  }

  Future<void> _search() => _run(() async {
    final hits = await _library.search(_query.text.trim());
    if (mounted) setState(() => _hits = hits);
  });

  Future<void> _answer(Future<GuardResponse> request) async {
    final response = await request;
    if (!mounted) return;
    response.ok
        ? showToast(context, response.message)
        : showError(context, response.message);
  }

  Future<void> _register(BookHit hit) => _run(() async {
    await _answer(
      widget.api.send('register', {'isbn': hit.isbn, 'pages': hit.pages}),
    );
    if (mounted) setState(() => _hits = const []);
  });

  Future<void> _setPages() => _run(
    () => _answer(
      widget.api.send('set_pages', {'pages': int.tryParse(_pages.text.trim())}),
    ),
  );

  Future<void> _attach() => _run(() async {
    final file = await widget.bookSource();
    if (file == null) return;
    await widget.api.uploadBook(file.name, await file.readAsBytes());
    if (mounted) {
      showToast(context, 'Uploaded - the PC indexes it in a few minutes.');
    }
  });

  @override
  Widget build(BuildContext context) {
    final book = widget.state?.book;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_busy) const LinearProgressIndicator(),
        const SectionHeader('Current book'),
        if (book == null)
          const Text('None yet - search below, or photograph the barcode.')
        else
          Card(
            child: ListTile(
              title: Text(book.title),
              subtitle: Text(_describe(book)),
            ),
          ),
        if (book != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pages,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Last page of your copy',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                onPressed: _busy ? null : _setPages,
                child: const Text('Set'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _busy ? null : _attach,
            icon: const Icon(Icons.attach_file),
            label: const Text('Attach ebook file (epub, pdf, mobi, ...)'),
          ),
        ],
        const SectionHeader('Find a book'),
        TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: 'Title, e.g. Atomic Habits',
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: _search,
            ),
          ),
        ),
        for (final hit in _hits)
          ListTile(
            title: Text(hit.title),
            subtitle: Text(
              '${hit.author.isEmpty ? '?' : hit.author} - '
              '${hit.pages ?? '?'} p - ISBN ${hit.isbn ?? 'none'}',
            ),
            trailing: const Icon(Icons.add),
            enabled: hit.isbn != null && !_busy,
            onTap: () => _register(hit),
          ),
      ],
    );
  }
}

String _describe(BookInfo book) {
  final author = book.author.isEmpty ? 'Unknown author' : book.author;
  final pages = book.pages == null ? 'last page not set' : 'p. ${book.pages}';
  final file = book.hasFile ? 'ebook attached' : 'no ebook file';
  return '$author - $pages - $file';
}
