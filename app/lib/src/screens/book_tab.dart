import 'dart:async';

import 'package:book_guard_app/src/book_formats.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/national_library.dart';
import 'package:book_guard_app/src/open_library.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/screens/book_description.dart';
import 'package:book_guard_app/src/screens/book_file_panel.dart';
import 'package:book_guard_app/src/screens/book_finder.dart';
import 'package:book_guard_app/src/screens/book_tab_cues.dart';
import 'package:book_guard_app/src/screens/edit_book_screen.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

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

  /// What the last upload step showed (a chip), kept until the next step.
  Widget? _note;

  /// The job being followed right after an upload or a retry, fresher
  /// than the 10-second snapshot; null once it has ended.
  IndexJob? _live;

  /// The failed job whose reason was last written to the error log.
  String _logged = '';

  @override
  void initState() {
    super.initState();
    _logged = logIndexFailure(widget.api, widget.state?.indexJob, _logged);
  }

  @override
  void didUpdateWidget(BookTab old) {
    super.didUpdateWidget(old);
    _logged = logIndexFailure(widget.api, widget.state?.indexJob, _logged);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (error) {
      if (mounted) reportFailure(context, widget.api, 'book', error);
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

  void _step(Widget note) => setState(() => _note = note);

  /// Shows the formats first, then picks, uploads and follows the indexing.
  Future<void> _attach() async {
    if (!await showBookFormats(context)) return;
    await _run(() async {
      final file = await widget.bookSource();
      if (file == null || !mounted) return;
      if (!isBookFile(file.name)) {
        showUnreadableFormat(context, file.name);
        return;
      }
      final since = widget.state?.indexJob?.updatedAt;
      _step(
        uploadStep(Icons.cloud_upload, 'Uploading', badge: Text(file.name)),
      );
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
    });
    if (!mounted) return;
    showReply(context, response);
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
    showFollowEnd(context, job);
  }

  /// A contents photo: waits for the PC's reading, then reports it.
  Future<void> _contents() => _run(() async {
    final file = await widget.photoSource(camera: !widget.desktop);
    if (file == null) return;
    _step(uploadStep(Icons.cloud_upload, 'Uploading the contents photo'));
    final (name, sent) = await widget.api.uploadPhoto(
      'toc-${file.name}',
      await file.readAsBytes(),
    );
    if (!mounted) return;
    if (!sent) {
      // Kept on the phone: the PC reads it once it is reachable.
      _step(queuedChip());
      return;
    }
    _step(uploadStep(Icons.hourglass_top, 'Waiting for the PC to read it'));
    final read = await widget.api.waitForPhoto(name);
    if (!mounted) return;
    final chapters = (await widget.api.fetchState())?.book?.chapters.length;
    if (!mounted) return;
    if (read != null && !read.accepted) {
      unawaited(widget.api.errors.log('photo', read.reason, {'photo': name}));
    }
    _step(contentsVerdict(read, chapters));
  });

  @override
  Widget build(BuildContext context) {
    final book = widget.state?.book;
    final note = _note;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (book == null)
          const EmptyGlyph(
            Icons.menu_book_outlined,
            semanticLabel: 'No book yet',
          )
        else
          Card(
            child: ListTile(
              isThreeLine: true,
              title: Text(book.title),
              subtitle: BookDescription(book),
              trailing: IconButton(
                icon: const Icon(Icons.edit, semanticLabel: 'Edit book'),
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
              GlyphButton(
                icon: widget.desktop ? Icons.upload_file : Icons.photo_camera,
                semanticLabel: 'Photograph contents',
                onPressed: _busy ? null : _contents,
              ),
              GlyphButton(
                icon: Icons.attach_file,
                semanticLabel: 'Attach book file',
                onPressed: _busy ? null : _attach,
              ),
            ],
          ),
          if (_live ?? widget.state?.indexJob case final job?) ...[
            const SizedBox(height: AppSpacing.sm),
            IndexJobCard(job: job, onRetry: _busy ? null : () => _retry(job)),
          ],
          if (note != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(alignment: Alignment.centerLeft, child: note),
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
