import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
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

/// "Read 13:40-14:29 (49 min)" and a button to narrow those times.
///
/// Only later starts and earlier ends: the PC refuses anything outside the
/// photos, and anything under 50 s a page (book-guard `_retime.py`). A
/// graded session shows its times without the button.
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
    final newStart = await showTimePicker(
      context: context,
      helpText: 'When did you start reading?',
      initialTime: TimeOfDay.fromDateTime(start.toLocal()),
    );
    if (newStart == null || !context.mounted) return;
    final newEnd = await showTimePicker(
      context: context,
      helpText: 'When did you stop?',
      initialTime: TimeOfDay.fromDateTime(end.toLocal()),
    );
    if (newEnd == null || !context.mounted) return;
    final startAt = onDayOf(first, newStart);
    final response = await api.sendQueued('session_times', {
      'session_id': session.id,
      'start': startAt.toIso8601String(),
      'end': onDayOf(startAt, newEnd).toIso8601String(),
    }, 'Times for p. ${session.startPage}-${session.endPage}');
    if (!context.mounted) return;
    response.ok
        ? showToast(context, response.message)
        : showError(context, response.message);
    unawaited(onChanged());
  }

  @override
  Widget build(BuildContext context) {
    final start = session.startedAt;
    final end = session.endedAt;
    if (start == null || end == null) return const SizedBox.shrink();
    final graded = session.status == 'credited' || session.status == 'failed';
    return Row(
      children: [
        Expanded(
          child: Text(
            'Read ${hhmm(start)}-${hhmm(end)} (${session.minutes} min)',
          ),
        ),
        if (!graded)
          TextButton(
            onPressed: () => _edit(context),
            child: const Text('Correct the times'),
          ),
      ],
    );
  }
}
