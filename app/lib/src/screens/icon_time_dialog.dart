import 'package:book_guard_app/src/screens/picker_parts.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Whether [end] lands on the day after [start] -- the same rule as
/// `onDayOf(startAt, end)` in `session_times.dart`: earlier than a minute
/// before the start rolls over.
bool endRollsOver(TimeOfDay start, TimeOfDay end) =>
    end.hour * 60 + end.minute < start.hour * 60 + start.minute - 1;

/// A start and an end, each as 24-hour hour and minute wheels, with no
/// words: a play icon marks the start row, a stop icon the end row, and a
/// `+1` badge shows when the end rolls over to the next day.
class IconTimeRangeDialog extends StatefulWidget {
  /// Creates the dialog opened on [initialStart]..[initialEnd].
  const new({required this.initialStart, required this.initialEnd, super.key});

  /// The start it opens on.
  final TimeOfDay initialStart;

  /// The end it opens on.
  final TimeOfDay initialEnd;

  @override
  State<IconTimeRangeDialog> createState() => _IconTimeRangeDialogState();
}

class _IconTimeRangeDialogState extends State<IconTimeRangeDialog> {
  late TimeOfDay _start = widget.initialStart;
  late TimeOfDay _end = widget.initialEnd;

  void _confirm() => Navigator.of(context).pop((start: _start, end: _end));

  Widget _row(
    IconData icon,
    String spoken,
    TimeOfDay time,
    ValueChanged<TimeOfDay> onChanged, {
    bool nextDay = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, semanticLabel: spoken),
        const SizedBox(width: AppSpacing.sm),
        NumberWheel(
          count: 24,
          value: time.hour,
          spoken: '$spoken hour',
          onChanged: (h) => onChanged(time.replacing(hour: h)),
        ),
        Text(':', style: theme.textTheme.headlineSmall),
        NumberWheel(
          count: 60,
          value: time.minute,
          spoken: '$spoken minute',
          onChanged: (m) => onChanged(time.replacing(minute: m)),
        ),
        SizedBox(
          width: AppSpacing.xl,
          child: nextDay
              ? Container(
                  key: const ValueKey('next-day'),
                  margin: const EdgeInsets.only(left: AppSpacing.xs),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: context.statusColors.warning,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    '+1',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: context.statusColors.onStatus,
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    contentPadding: const EdgeInsets.all(AppSpacing.md),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(
          Icons.play_arrow,
          'Start',
          _start,
          (t) => setState(() => _start = t),
        ),
        const SizedBox(height: AppSpacing.sm),
        _row(
          Icons.stop,
          'End',
          _end,
          (t) => setState(() => _end = t),
          nextDay: endRollsOver(_start, _end),
        ),
      ],
    ),
    actions: pickerActions(context, _confirm),
  );
}
