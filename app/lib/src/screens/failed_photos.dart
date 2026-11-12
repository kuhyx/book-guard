import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/failed_photo.dart';
import 'package:book_guard_app/src/screens/failed_photo_card.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/report_dialog.dart';
import 'package:book_guard_app/src/screens/type_page_dialog.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:book_guard_app/src/ui/hold_button.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

export 'package:book_guard_app/src/screens/failed_photo.dart';

/// The failed photos, each with "box the number" (the PC reads it again
/// inside the box) and "this should not fail" (a bug report: the photo,
/// what both readers made of it and what it really shows, sent to the PC's
/// `Reading/logs/reports/`), and "dismiss" / "clear all", which only hide
/// cards on this device (a later failure with a new name still shows).
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

  /// Names hidden on this device; null until read from the store.
  Set<String>? _dismissed;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.api.dismissedPhotos().then((names) {
        if (mounted) setState(() => _dismissed = names);
      }),
    );
  }

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
    // The number the phone read in the box is the page; the PC takes it.
    final response = await widget.api.sendQueued('box', {
      'photo': failed.entry.name,
      'box': [box.left, box.top, box.right, box.bottom],
      'page': ?result?.page,
    });
    if (!mounted) return;
    showReply(context, response);
    unawaited(widget.onChanged());
  }

  Future<void> _type(FailedPhoto failed) async {
    await typePage(
      context,
      widget.api,
      failed.entry.name,
      initial: failed.pencil,
    );
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
    showCue(
      context,
      const Cue(
        CueKind.ok,
        icon: Icons.flag,
        semanticLabel: 'report saved, it reaches the PC with the next upload',
      ),
    );
  }

  Future<void> _dismiss(Iterable<FailedPhoto> failed) async {
    final names = [for (final f in failed) f.entry.name];
    setState(() => _dismissed?.addAll(names));
    for (final name in names) {
      await widget.api.dismissPhoto(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = _dismissed;
    if (hidden == null) return const SizedBox.shrink();
    final failed = [
      for (final f in failedPhotos(widget.state, widget.journal))
        if (!hidden.contains(f.entry.name)) f,
    ];
    if (failed.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error_outline, semanticLabel: 'failed photos'),
            const SizedBox(width: AppSpacing.sm),
            Text('${failed.length}'),
            const Spacer(),
            // Hides every card at once: held, not tapped.
            if (failed.length > 1)
              HoldButton(
                icon: Icons.clear_all,
                semanticLabel: 'Clear all',
                onConfirmed: () => unawaited(_dismiss(failed)),
              ),
          ],
        ),
        // A sideways strip, as tall as its tallest card: however many
        // failed, the page never scrolls vertically.
        LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, f) in failed.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    // One card at a time, the next one peeking in.
                    width: box.maxWidth * (failed.length == 1 ? 1 : 0.85),
                    child: _card(f),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(FailedPhoto f) => FutureBuilder<(Uint8List?, bool)>(
    future: _loads[f.entry.name] ??= _load(f.entry.name),
    builder: (context, snap) {
      final bytes = snap.data?.$1;
      return FailedPhotoCard(
        failed: f,
        bytes: bytes,
        reported: (snap.data?.$2 ?? false) || _reported.contains(f.entry.name),
        onBox: f.pc != null && widget.reader != null ? () => _box(f) : null,
        // No number read by the phone, nor by the PC (which may not have
        // the photo yet: it can still sit in the outbox).
        onType: f.entry.page == null && f.pc?.page == null
            ? () => unawaited(_type(f))
            : null,
        onReport: bytes == null ? null : () => _report(f),
        onDismiss: () => _dismiss([f]),
      );
    },
  );
}
