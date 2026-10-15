import 'package:book_guard_app/src/pace/day_views.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `Thu 15.10`.
String shortDay(DateTime day) =>
    '${_weekdays[pyWeekday(day)]} '
    '${day.day.toString().padLeft(2, '0')}.'
    '${day.month.toString().padLeft(2, '0')}';

/// `October 2026`.
String monthTitle(DateTime first) =>
    '${_months[first.month - 1]} ${first.year}';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The weekday initials, Mon first.
List<String> get weekdayInitials => [for (final d in _weekdays) d[0]];

/// What a cell shows under the date: `22/17` (credited/required), `34`
/// (future: required), `free`, `old 53` (before the switch), or `-`.
String cellText(DayView v) {
  if (v.beforeQuotas) return '-';
  if (v.free) return 'free';
  if (v.oldRule) return 'old ${v.credited}';
  if (v.kind == DayKind.future) return '${v.required}';
  return '${v.credited}/${v.required}';
}

/// Whether the day's credited pages reached its requirement (past/today).
bool met(DayView v) =>
    v.kind != DayKind.future &&
    !v.oldRule &&
    !v.beforeQuotas &&
    v.credited >= v.required;

/// Everything about one day, as lines (the day card).
List<String> dayLines(DayView v) {
  final p = v.pace;
  final when = switch (v.kind) {
    DayKind.past => 'as it stood that morning',
    DayKind.today => 'today, live',
    DayKind.future => 'projected: every day before it meets its requirement',
  };
  if (v.beforeQuotas) return ['${shortDay(v.day)}: no page quota yet'];
  if (v.oldRule) {
    return [oldRuleText, 'Credited that day: ${v.credited} pages'];
  }
  final behind = p.behind > 0 ? ' (${p.behind} behind)' : ' (on pace)';
  final delta = '${v.simulated > 0 ? '+' : ''}${v.simulated}';
  final debt = p.carriedDebt > 0 ? ' (carried debt ${p.carriedDebt})' : '';
  final credit = p.carriedCredit > 0
      ? ' (carried credit ${p.carriedCredit})'
      : '';
  return [
    '${shortDay(v.day)}, $when',
    if (v.free)
      'Free day: asks nothing'
    else if (v.kind == DayKind.future)
      'Requirement: ${v.required} pages'
    else
      'Requirement: ${v.required} pages; credited ${v.credited}',
    if (v.simulated != 0)
      'Simulated: ${v.assumed} read ($delta)'
    else if (v.kind == DayKind.future)
      'Assumed read: ${v.assumed}',
    'Line at the start of the day ${p.line}; read ${p.pages}$behind',
    'Month target ${p.target}$debt$credit',
  ];
}

/// One day in the week row or the month grid; tap selects it.
class DayCell extends StatelessWidget {
  /// Creates a cell.
  const new({
    required this.view,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// The day.
  final DayView view;

  /// The top line: weekday initial or day of month.
  final String label;

  /// Whether it is the day shown in the day card.
  final bool selected;

  /// Selects it.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final v = view;
    final missed =
        v.kind == DayKind.past &&
        !v.free &&
        !v.oldRule &&
        !v.beforeQuotas &&
        !met(v);
    final fill = met(v)
        ? status.success.withValues(alpha: 0.25)
        : missed
        ? status.danger.withValues(alpha: 0.2)
        : null;
    final border = selected
        ? theme.colorScheme.primary
        : v.kind == DayKind.today
        ? status.info
        : theme.dividerColor;
    final muted = v.kind == DayKind.future || v.free;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              Text(
                cellText(v),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted ? theme.hintColor : null,
                  fontWeight: v.simulated != 0 ? FontWeight.bold : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
