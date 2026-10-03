import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/error_log.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Takes a photo: the camera on the phone, a file on the desktop. Returns
/// the original file untouched -- no size or quality options, because any
/// re-encode would strip the EXIF capture time the session clock runs on.
typedef PhotoSource = Future<XFile?> Function({required bool camera});

final _epoch = DateTime.utc(1970);

/// The default [PhotoSource]: the camera, or the gallery on the desktop.
Future<XFile?> pickPhoto({required bool camera}) => ImagePicker().pickImage(
  source: camera ? ImageSource.camera : ImageSource.gallery,
);

/// What the page number of a [label] photo has to fit, from the snapshot,
/// this phone's [journal] and the page reading started at.
PageContext pageContextFor(
  String label,
  GuardState? state,
  List<JournalEntry> journal,
  int? openStart,
) {
  final lastPage = state?.book?.pages;
  if (label.startsWith('check')) {
    return PageContext(
      expected: int.tryParse(label.substring(5)),
      lastPage: lastPage,
    );
  }
  if (label == 'stop') return PageContext(after: openStart, lastPage: lastPage);
  final ends = [
    for (final e in journal)
      if (e.label == 'stop' && e.page != null) e.page!,
  ];
  final sessions = [...?state?.sessions]
    ..sort((a, b) => (a.startedAt ?? _epoch).compareTo(b.startedAt ?? _epoch));
  final pcEnd = sessions.isEmpty ? null : sessions.last.endPage;
  return PageContext(
    near: ends.isNotEmpty ? ends.last : pcEnd,
    lastPage: lastPage,
  );
}

/// Reads the photo on the device and lets the reader confirm or box the
/// number. Null if they chose to retake it; an empty result when there is
/// no reader (desktop) or the image could not be read (logged).
Future<ReviewResult?> reviewPhoto(
  BuildContext context, {
  required PageReader? reader,
  required Uint8List bytes,
  required String fileName,
  required PageContext pageContext,
  required ErrorLog errors,
}) async {
  if (reader == null) return const ReviewResult();
  final scan = await reader.scan(bytes);
  if (scan == null) {
    unawaited(errors.log('reader', 'unreadable image', {'photo': fileName}));
    return const ReviewResult();
  }
  if (!context.mounted) return null;
  return await Navigator.of(context).push<ReviewResult>(
    MaterialPageRoute(
      builder: (_) => PhotoReview(
        bytes: bytes,
        scan: scan,
        reader: reader,
        context: pageContext,
      ),
    ),
  );
}

/// Why the summary waits, when the PC's grader (Claude) is down.
String? graderNote(GuardState? state) {
  final since = state?.claudeDownSince?.toLocal();
  if (since == null) return null;
  final hhmm =
      '${since.hour.toString().padLeft(2, '0')}:'
      '${since.minute.toString().padLeft(2, '0')}';
  return 'The grader (Claude on the PC) has been unavailable since $hhmm. '
      'Your summary is kept and graded automatically once it is back - '
      'nothing is lost.';
}

/// The summary box for [session].
class SummarySection extends StatelessWidget {
  /// Creates the section.
  const new({
    required this.session,
    required this.controller,
    required this.onSubmit,
    super.key,
    this.grader,
    this.times,
    this.enabled = true,
  });

  /// False while the grader has it: the text is locked.
  final bool enabled;

  /// When it was read, with "Correct the times".
  final Widget? times;

  /// The session to summarise.
  final SessionInfo session;

  /// The summary text.
  final TextEditingController controller;

  /// Sends it; null while busy.
  final VoidCallback? onSubmit;

  /// Why grading may wait, if it may.
  final String? grader;

  @override
  Widget build(BuildContext context) {
    final grader = this.grader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Summary for p. ${session.startPage}-${session.endPage}'),
        ?times,
        const Text(
          '3-5 sentences in your own words (Polish or English) about what '
          'happened in these pages.',
        ),
        if (grader != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            grader,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller,
          enabled: enabled,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(onPressed: onSubmit, child: const Text('Submit summary')),
      ],
    );
  }
}

/// The grader's answer: green when credited, red when not.
class VerdictText extends StatelessWidget {
  /// Creates the line.
  const new(this.verdict, {required this.passed, super.key});

  /// What the PC said.
  final String verdict;

  /// Credited, failed, or null for "not decided yet".
  final bool? passed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Text(
        verdict,
        style: TextStyle(
          color: switch (passed) {
            true => theme.extension<AppStatusColors>()?.success,
            false => theme.colorScheme.error,
            null => null,
          },
        ),
      ),
    );
  }
}

/// What to photograph next, and how many photos still wait for the PC.
class SessionPrompt extends StatelessWidget {
  /// Creates the prompt.
  const new({required this.reading, required this.waiting, super.key});

  /// The page reading started at, or null when not reading.
  final int? reading;

  /// Photos taken here that the PC has not read yet.
  final int waiting;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeader('Session photos'),
      Text(
        reading == null
            ? 'Photograph the open page (number visible) when you start.'
            : 'Reading since p. $reading - photograph the page where you '
                  'stop.',
      ),
      if (waiting > 0) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$waiting photo(s) taken here are not read by the PC yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );
}
