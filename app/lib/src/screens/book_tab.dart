import 'dart:async';

import 'package:book_guard_app/src/book_formats.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/national_library.dart';
import 'package:book_guard_app/src/open_library.dart';
import 'package:book_guard_app/src/screens/book_file_panel.dart';
import 'package:book_guard_app/src/screens/book_finder.dart';
import 'package:book_guard_app/src/screens/edit_book_screen.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

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
    this.bookSource = pickBookFile,
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

  /// The job being followed right after an upload or a retry, fresher
  /// than the 10-second snapshot; null once it has ended.
  IndexJob? _live;

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

  /// Shows the formats first, then picks, uploads and follows the indexing.
  Future<void> _attach() async {
    if (!await showBookFormats(context)) return;
    await _run(() async {
      final file = await widget.bookSource();
      if (file == null || !mounted) return;
      if (!isBookFile(file.name)) {
        showError(context, '${file.name}: the PC cannot read this format.');
        return;
      }
      final since = widget.state?.indexJob?.updatedAt;
      setState(() => _note = 'Uploading ${file.name}...');
      // The name the PC files it under: its index_job.file.
      final name = widget.api.safeName(file.name);
      await widget.api.uploadBook(file.name, await file.readAsBytes());
      if (!mounted) return;
      setState(() => _note = null);
      await _follow(name, since);
    });
  }

  /// Queues a failed (or stalled) file again -- offline too, through the
  /// outbox; the 10-second refresh then shows its progress.
  Future<void> _retry(IndexJob job) => _run(() async {
    final response = await widget.api.sendQueued('retry_book', {
      'file': job.file,
    }, 'Retry of ${job.file}');
    if (!mounted) return;
    response.ok
        ? showToast(context, response.message)
        : showError(context, response.message);
  });

  /// Polls the PC until the job for [name] (newer than [since]) ends.
  Future<void> _follow(String name, DateTime? since) async {
    setState(() => _live = IndexJob(file: name, stage: 'uploaded'));
    bool fresh(IndexJob? job) =>
        job != null && job.file == name && job.updatedAt != since;
    final state = await widget.api.waitFor((s) {
      if (fresh(s.indexJob) && mounted) setState(() => _live = s.indexJob);
      return fresh(s.indexJob) && s.indexJob!.finished;
    });
    if (!mounted) return;
    final job = state?.indexJob;
    setState(() => _live = null);
    if (job == null) {
      showToast(context, 'Still indexing - progress keeps showing here.');
    } else if (job.stage == 'done') {
      showToast(context, 'Book file attached.');
    }
  }

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
                label: const Text('Attach book file'),
              ),
            ],
          ),
          if (_live ?? widget.state?.indexJob case final job?) ...[
            const SizedBox(height: AppSpacing.sm),
            IndexJobCard(job: job, onRetry: _busy ? null : () => _retry(job)),
          ],
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
