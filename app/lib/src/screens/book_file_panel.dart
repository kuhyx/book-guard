import 'package:book_guard_app/src/book_formats.dart';
import 'package:book_guard_app/src/index_job.dart';
import 'package:design_system/design_system.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

/// The formats the PC reads, by tool; true when "Choose file" is tapped.
Future<bool> showBookFormats(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final heading = Theme.of(context).textTheme.titleSmall;
        return AlertDialog(
          title: const Text('Attach book file'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('The PC can read these formats:'),
                for (final group in bookFormatGroups) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(group.label, style: heading),
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose file'),
            ),
          ],
        );
      },
    ) ??
    false;

/// Where the PC's indexing of a book file stands; failed (or silent for
/// 30 minutes) shows the reason in red with a Retry button.
class IndexJobCard extends StatelessWidget {
  /// Creates the card; [onRetry] null disables Retry.
  const new({required this.job, required this.onRetry, super.key});

  /// The job, from `state.json`.
  final IndexJob job;

  /// Queues the file again.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final failed = job.hasFailed(now);
    final error = Theme.of(context).colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              job.describe(now),
              style: failed ? TextStyle(color: error) : null,
            ),
            if (!job.finished && !failed) ...[
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(value: job.fraction),
            ],
            if (failed)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
