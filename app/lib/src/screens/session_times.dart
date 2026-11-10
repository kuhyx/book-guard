import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/screens/icon_pickers.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// `HH:MM` in local time.
String hhmm(DateTime moment) {
  final local = moment.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// [time] on [day]'s date, moved a day on if that is before [day] (a
/// session that ran past midnight).
DateTime onDayOf(DateTime day, TimeOfDay time) {
  final local = day.toLocal();
  final moment = DateTime(
    local.year,
    local.month,
    local.day,
    time.hour,
    time.minute,
  );
  return moment.isBefore(local.subtract(const Duration(minutes: 1)))
      ? moment.add(const Duration(days: 1))
      : moment;
}

/// `13:40-14:29` and the minutes beside clock glyphs, and a button to narrow
/// those times.
///
/// Only later starts and earlier ends: the PC refuses anything outside the
/// photos, and anything under 50 s a page (book-guard `_retime.py`). A
/// graded session shows its times without the button. The two pickers are
/// told apart by a play (start) or stop (end) glyph above each.
class SessionTimes extends StatelessWidget {
  /// Creates the line for [session].
  const new({
    required this.api,
    required this.session,
    required this.onChanged,
    super.key,
  });

  /// Sends the change.
  final GuardApi api;

  /// The session.
  final SessionInfo session;

  /// Refetch after a change.
  final Future<void> Function() onChanged;

  Future<void> _edit(BuildContext context) async {
    final start = session.startedAt;
    final end = session.endedAt;
    final first = session.photoStart;
    if (start == null || end == null || first == null) return;
    final picked = await showIconTimeRangePicker(
      context: context,
      initialStart: TimeOfDay.fromDateTime(start.toLocal()),
      initialEnd: TimeOfDay.fromDateTime(end.toLocal()),
    );
    if (picked == null || !context.mounted) return;
    final startAt = onDayOf(first, picked.start);
    final response = await api.sendQueued('session_times', {
      'session_id': session.id,
      'start': startAt.toIso8601String(),
      'end': onDayOf(startAt, picked.end).toIso8601String(),
    });
    if (!context.mounted) return;
    showCue(context, replyCue(response), badge: _badge(response));
    unawaited(onChanged());
  }

  /// The numbers a refusal carries: the photos' span, or pages and minutes.
  static Widget? _badge(GuardResponse response) {
    final data = response.data;
    if (data == null) return null;
    return switch (response.code) {
      'outside_photos' => Text('${data['first']}-${data['last']}'),
      'too_short' => Text('${data['pages']} / ${data['minutes']}'),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final start = session.startedAt;
    final end = session.endedAt;
    if (start == null || end == null) return const SizedBox.shrink();
    final graded = session.graded;
    return Row(
      children: [
        const Icon(Icons.schedule, size: 18, semanticLabel: 'Read'),
        const SizedBox(width: AppSpacing.xs),
        Text('${hhmm(start)}-${hhmm(end)}'),
        const SizedBox(width: AppSpacing.md),
        IconNumber(
          Icons.timer_outlined,
          '${session.minutes}',
          semanticLabel: 'Minutes',
        ),
        const Spacer(),
        if (!graded)
          IconButton(
            onPressed: () => _edit(context),
            icon: const Icon(
              Icons.more_time,
              semanticLabel: 'Correct the times',
            ),
          ),
      ],
    );
  }
}
