import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/report_dialog.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// One photo taken here that did not come out as it should.
class FailedPhoto {
  /// Creates one.
  const new({required this.entry, required this.reason, this.pc});

  /// The phone's record of it.
  final JournalEntry entry;

  /// What went wrong, in words.
  final String reason;

  /// The PC's reading, once it has one.
  final PhotoInfo? pc;
}

/// The photos taken here that failed: the PC rejected them, or the phone
/// could not read a page number and the PC has not read them yet.
List<FailedPhoto> failedPhotos(GuardState? state, List<JournalEntry> journal) {
  final byName = {
    for (final p in state?.photos ?? const <PhotoInfo>[]) p.name: p,
  };
  return [
    for (final e in journal.reversed)
      if (byName[e.name] case final pc? when !pc.accepted)
        FailedPhoto(entry: e, reason: pc.caption, pc: pc)
      else if (!byName.containsKey(e.name) && e.page == null)
        FailedPhoto(entry: e, reason: 'the phone found no page number'),
  ];
}

/// The failed photos, each with "box the number" (the PC reads it again
/// inside the box) and "this should not fail" (a bug report: the photo,
/// what both readers made of it and what it really shows, sent to the PC's
/// `Reading/logs/reports/`).
class FailedPhotos extends StatefulWidget {
  /// Creates the section.
  const new({
    required this.api,
    required this.state,
    required this.journal,
    required this.onChanged,
    super.key,
    this.reader,
  });

  /// The PC.
  final GuardApi api;

  /// The latest snapshot.
  final GuardState? state;

  /// Every photo taken here.
  final List<JournalEntry> journal;

  /// On-device reading; null on the desktop.
  final PageReader? reader;

  /// Refetch after an action.
  final Future<void> Function() onChanged;

  @override
  State<FailedPhotos> createState() => _FailedPhotosState();
}

class _FailedPhotosState extends State<FailedPhotos> {
  final _bytes = <String, Uint8List?>{};
  final _reported = <String>{};

  final _loads = <String, Future<(Uint8List?, bool)>>{};

  Future<Uint8List?> _photo(String name) async =>
      _bytes[name] ??= await widget.api.localPhoto(name);

  Future<(Uint8List?, bool)> _load(String name) async =>
      (await _photo(name), await widget.api.reported(name));

  Future<void> _box(FailedPhoto failed) async {
    final reader = widget.reader;
    final bytes = await _photo(failed.entry.name);
    if (reader == null || bytes == null || !mounted) return;
    final scan = await reader.scan(bytes);
    if (scan == null || !mounted) return;
    final label = failed.entry.label;
    final result = await Navigator.of(context).push<ReviewResult>(
      MaterialPageRoute(
        builder: (_) => PhotoReview(
          bytes: bytes,
          scan: scan,
          reader: reader,
          context: PageContext(
            expected: label.startsWith('check')
                ? int.tryParse(label.substring(5))
                : null,
          ),
        ),
      ),
    );
    final box = result?.box;
    if (box == null || !mounted) return;
    final response = await widget.api.sendQueued('box', {
      'photo': failed.entry.name,
      'box': [box.left, box.top, box.right, box.bottom],
    }, 'Re-read of ${failed.entry.name}');
    if (!mounted) return;
    response.ok
        ? showToast(context, response.message)
        : showError(context, response.message);
    unawaited(widget.onChanged());
  }

  Future<void> _report(FailedPhoto failed) async {
    final bytes = await _photo(failed.entry.name);
    if (bytes == null || !mounted) return;
    final answer = await showDialog<(int?, String)>(
      context: context,
      builder: (_) => ReportDialog(reason: failed.reason),
    );
    if (answer == null) return;
    final (said, note) = answer;
    final entry = failed.entry;
    await widget.api.reportPhoto(
      name: entry.name,
      bytes: bytes,
      detail: {
        'label': entry.label,
        'taken_at': entry.takenAt.toIso8601String(),
        'phone_page': entry.page,
        'pc_status': failed.pc?.status,
        'pc_reason': failed.pc?.reason,
        'failure': failed.reason,
        'actual_page': said,
        'comment': note,
      },
    );
    await widget.api.flush();
    if (!mounted) return;
    setState(() => _reported.add(entry.name));
    showToast(
      context,
      'Report saved - it reaches the PC with the next upload.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final failed = failedPhotos(widget.state, widget.journal);
    if (failed.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Failed photos'),
        for (final f in failed)
          FutureBuilder<(Uint8List?, bool)>(
            future: _loads[f.entry.name] ??= _load(f.entry.name),
            builder: (context, snap) {
              final bytes = snap.data?.$1;
              final reported =
                  (snap.data?.$2 ?? false) || _reported.contains(f.entry.name);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        height: 96,
                        child: bytes == null
                            ? const Icon(Icons.image_not_supported)
                            : Image.memory(
                                bytes,
                                fit: BoxFit.cover,
                                cacheWidth: 144,
                              ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${f.entry.label}: ${f.reason}'),
                            Wrap(
                              spacing: AppSpacing.xs,
                              children: [
                                if (f.pc != null && widget.reader != null)
                                  TextButton(
                                    onPressed: () => _box(f),
                                    child: const Text('Box the number'),
                                  ),
                                TextButton(
                                  onPressed: reported || bytes == null
                                      ? null
                                      : () => _report(f),
                                  child: Text(
                                    reported
                                        ? 'Reported'
                                        : 'This should not fail',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
