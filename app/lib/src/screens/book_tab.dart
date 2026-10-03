import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/national_library.dart';
import 'package:book_guard_app/src/open_library.dart';
import 'package:book_guard_app/src/screens/book_finder.dart';
import 'package:book_guard_app/src/screens/edit_book_screen.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
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

/// This month's book: find it (see [BookFinder]), register it, attach its file.
class BookTab extends StatefulWidget {
  /// Creates the tab.
  const new({
    required this.api,
    required this.state,
    required this.onChanged,
    super.key,
    this.library,
    this.nationalLibrary,
    this.bookSource = _pickBook,
    this.photoSource = pickPhoto,
    this.desktop = false,
  });

  /// The PC.
  final GuardApi api;

  /// The latest snapshot.
  final GuardState? state;

  /// Refetch after an action.
  final Future<void> Function() onChanged;

  /// Title search; replaced in tests.
  final OpenLibrary? library;

  /// Polish catalogue search; replaced in tests.
  final NationalLibrary? nationalLibrary;

  /// Where the book file comes from.
  final BookFileSource bookSource;

  /// Where the contents photo comes from.
  final PhotoSource photoSource;

  /// Desktop: pick a file instead of opening the camera.
  final bool desktop;

  @override
  State<BookTab> createState() => _BookTabState();
}

class _BookTabState extends State<BookTab> {
  late final OpenLibrary _library = widget.library ?? OpenLibrary();
  late final NationalLibrary _national =
      widget.nationalLibrary ?? NationalLibrary();
  bool _busy = false;
  String? _note;

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

  Future<void> _edit(BookInfo book) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditBookScreen(api: widget.api, book: book),
      ),
    );
    if (saved ?? false) await widget.onChanged();
  }

  /// Waits for the PC to index the file before unlocking the button.
  Future<void> _attach() => _run(() async {
    final file = await widget.bookSource();
    if (file == null) return;
    setState(() => _note = 'Uploading ${file.name}...');
    await widget.api.uploadBook(file.name, await file.readAsBytes());
    if (!mounted) return;
    setState(() => _note = 'Uploaded - the PC is indexing it...');
    final done = await widget.api.waitFor((s) => s.book?.hasFile ?? false);
    if (!mounted) return;
    final note = done == null
        ? 'The PC has not indexed it yet - it will when it is on.'
        : 'Ebook attached.';
    setState(() => _note = note);
    done == null ? showError(context, note) : showToast(context, note);
  });

  /// A contents photo: waits for the PC's reading, then reports it.
  Future<void> _contents() => _run(() async {
    final file = await widget.photoSource(camera: !widget.desktop);
    if (file == null) return;
    setState(() => _note = 'Uploading the contents photo...');
    final (name, sent) = await widget.api.uploadPhoto(
      'toc-${file.name}',
      await file.readAsBytes(),
    );
    if (!mounted) return;
    if (!sent) {
      setState(
        () => _note =
            'Saved on the phone - the PC reads the contents once it is '
            'reachable.',
      );
      return;
    }
    setState(() => _note = 'Uploaded - waiting for the PC to read it...');
    final read = await widget.api.waitForPhoto(name);
    if (!mounted) return;
    final chapters = (await widget.api.fetchState())?.book?.chapters.length;
    if (!mounted) return;
    final note = read == null || !read.accepted || chapters == null
        ? photoVerdict(read)
        : 'Contents read - the book has $chapters chapters.';
    setState(() => _note = note);
    read != null && read.accepted
        ? showToast(context, note)
        : showError(context, note);
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
              trailing: IconButton(
                tooltip: 'Edit book',
                icon: const Icon(Icons.edit),
                onPressed: _busy ? null : () => _edit(book),
              ),
            ),
          ),
        if (book != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _contents,
                icon: Icon(
                  widget.desktop ? Icons.upload_file : Icons.photo_camera,
                ),
                label: const Text('Photograph contents'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _attach,
                icon: const Icon(Icons.attach_file),
                label: const Text('Attach ebook file'),
              ),
            ],
          ),
          if (_note case final note?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(note),
          ],
        ],
        BookFinder(
          api: widget.api,
          onChanged: widget.onChanged,
          library: _library,
          nationalLibrary: _national,
        ),
      ],
    );
  }
}

String _describe(BookInfo book) {
  final author = book.author.isEmpty ? 'Unknown author' : book.author;
  final pages = book.pages == null ? 'last page not set' : 'p. ${book.pages}';
  final file = book.hasFile ? 'ebook attached' : 'no ebook file';
  final chapter =
      book.chapter?.label ??
      (book.chapters.isEmpty ? null : '${book.chapters.length} chapters');
  return ['$author - $pages - $file', ?chapter].join('\n');
}
