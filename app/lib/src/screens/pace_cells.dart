import 'package:book_guard_app/src/pace/day_views.dart';
import 'package:book_guard_app/src/screens/icon_num.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// `15.10`: day and month as numerals.
String shortDay(DateTime day) =>
    '${day.day.toString().padLeft(2, '0')}.'
    '${day.month.toString().padLeft(2, '0')}';

/// `10 · 2026`.
String monthTitle(DateTime first) =>
    '${first.month.toString().padLeft(2, '0')} · ${first.year}';

/// Whether [day] is a Saturday or a Sunday.
bool isWeekend(DateTime day) => pyWeekday(day) >= 5;

/// What a cell shows under the date: a glyph, a number, or both.
typedef CellMark = ({IconData? icon, String number});

/// `22/17` (credited/required), `17` (future: required), a free-day or
/// sick-day glyph, the history glyph with the credited pages (before the
/// switch), or a bare `-`; the simulated day shows its simulated total,
/// `27/17` (the cell is bold).
CellMark cellMark(DayView v) {
  if (v.beforeQuotas) return (icon: null, number: '-');
  if (v.simulated != 0) {
    return (icon: null, number: '${v.assumed}/${v.required}');
  }
  if (v.free) return (icon: freeGlyph, number: '');
  if (v.sick) return (icon: sickGlyph, number: '');
  if (v.oldRule) return (icon: Icons.history, number: '${v.credited}');
  if (v.kind == DayKind.future) return (icon: null, number: '${v.required}');
  return (icon: null, number: '${v.credited}/${v.required}');
}

/// Whether the day's pages reached its requirement (past/today): the
/// simulated total on the simulated day, else the credited pages.
bool met(DayView v) =>
    v.kind != DayKind.future &&
    !v.oldRule &&
    !v.beforeQuotas &&
    (v.simulated != 0 ? v.assumed : v.credited) >= v.required;

/// A past day that asked something and fell short.
bool missed(DayView v) =>
    v.kind == DayKind.past &&
    !v.free &&
    !v.sick &&
    !v.oldRule &&
    !v.beforeQuotas &&
    !met(v);

/// One dot for a weekday: a weekend day is larger and in the accent colour.
class WeekdayDot extends StatelessWidget {
  /// Creates the dot.
  const new({required this.weekend, super.key});

  /// Whether it marks Saturday or Sunday.
  final bool weekend;

  @override
  Widget build(BuildContext context) {
    final size = weekend ? 10.0 : 5.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: weekend
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).hintColor,
      ),
    );
  }
}

/// Seven dots, Monday first, over a month grid.
class WeekdayDots extends StatelessWidget {
  /// Creates the row.
  const new({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(child: WeekdayDot(weekend: i >= 5)),
          ),
      ],
    ),
  );
}

/// One day in the week row or the month grid; tap selects it.
class DayCell extends StatelessWidget {
  /// Creates a cell.
  const new({
    required this.view,
    required this.selected,
    required this.onTap,
    this.showDot = false,
    super.key,
  });

  /// The day.
  final DayView view;

  /// Whether it is the day shown in the day card.
  final bool selected;

  /// Selects it.
  final VoidCallback onTap;

  /// Whether the weekday dot sits over the date (the week row).
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final v = view;
    final reached = met(v);
    final fell = missed(v);
    final fill = reached
        ? status.success.withValues(alpha: 0.25)
        : fell
        ? status.danger.withValues(alpha: 0.2)
        : null;
    final border = selected
        ? theme.colorScheme.primary
        : v.kind == DayKind.today
        ? status.info
        : theme.dividerColor;
    final muted = v.kind == DayKind.future || v.free || v.sick;
    final mark = cellMark(v);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: muted ? theme.hintColor : null,
      fontWeight: v.simulated != 0 ? FontWeight.bold : null,
    );
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            children: [
              if (showDot) WeekdayDot(weekend: isWeekend(v.day)),
              FittedBox(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${v.day.day}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: v.kind == DayKind.today
                            ? FontWeight.bold
                            : null,
                      ),
                    ),
                    if (reached)
                      Icon(Icons.check, size: 12, color: status.success)
                    else if (fell)
                      Icon(Icons.close, size: 12, color: status.danger),
                  ],
                ),
              ),
              FittedBox(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (mark.icon case final icon?)
                      Icon(
                        icon,
                        size: 14,
                        color: muted ? theme.hintColor : null,
                      ),
                    Text(
                      mark.number,
                      style: style,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
