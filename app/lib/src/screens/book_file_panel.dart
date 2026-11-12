import 'package:book_guard_app/src/book_formats.dart';
import 'package:book_guard_app/src/index_job.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Picks a book file; replaced in tests.
typedef BookFileSource = Future<XFile?> Function();

/// Picks a book file.
///
/// Android gets no filter at all: file_selector turns extensions into MIME
/// types through `MimeTypeMap` (dropping the ones it does not know) and
/// the document picker greys out every file whose *reported* MIME type is
/// not on that list -- and a provider can report a `.mobi`, `.fb2` or
/// `.azw3` as `application/octet-stream`. The caller checks the extension.
Future<XFile?> pickBookFile() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? openFile()
    : openFile(
        acceptedTypeGroups: [
          XTypeGroup(label: 'Book files', extensions: bookExtensions),
        ],
      );

/// The formats the PC reads, one chip per extension and a divider between
/// the tools' groups; true when the folder button is tapped.
Future<bool> showBookFormats(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, group) in bookFormatGroups.indexed) ...[
                if (i > 0) const Divider(height: AppSpacing.lg),
                // One widget per extension: a joined line breaks inside
                // ".azw3" (Unicode forbids a break before "." after a
                // space, so it breaks after the dot instead).
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final e in group.extensions)
                      Text('.$e', softWrap: false),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
          ),
          IconButton.filled(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.folder_open, semanticLabel: 'Choose file'),
          ),
        ],
      ),
    ) ??
    false;

/// The glyph for an indexing stage; `failed` and a stalled job look
/// different, both red.
IconData indexStageIcon(IndexJob job, {required bool stale}) {
  if (stale) return Icons.timer_off;
  return switch (job.stage) {
    'uploaded' => Icons.cloud_done,
    'extracting' => Icons.text_snippet,
    'embedding' => Icons.scatter_plot,
    'done' => Icons.check_circle,
    'failed' => Icons.error,
    _ => Icons.help_outline,
  };
}

/// Where the PC's indexing of a book file stands: the file's name, a stage
/// glyph and a progress bar; failed (or silent for 30 minutes) turns red
/// with a retry button. The reason it failed goes to the error log.
class IndexJobCard extends StatelessWidget {
  /// Creates the card; [onRetry] null disables the retry button.
  const new({required this.job, required this.onRetry, super.key});

  /// The job, from `state.json`.
  final IndexJob job;

  /// Queues the file again.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final failed = job.hasFailed(now);
    final colors = context.statusColors;
    final tint = failed
        ? colors.danger
        : job.stage == 'done'
        ? colors.success
        : Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  indexStageIcon(job, stale: job.isStale(now)),
                  color: tint,
                  semanticLabel: job.stage,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(job.file, overflow: TextOverflow.ellipsis),
                ),
                if (job.stage == 'embedding' && !failed)
                  Text('${job.done}/${job.total}'),
                if (job.stage == 'done') Text('${job.total}'),
                if (failed)
                  GlyphButton(
                    icon: Icons.refresh,
                    semanticLabel: 'Retry',
                    onPressed: onRetry,
                    color: colors.danger,
                  ),
              ],
            ),
            if (!job.finished && !failed) ...[
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(value: job.fraction),
            ],
          ],
        ),
      ),
    );
  }
}
