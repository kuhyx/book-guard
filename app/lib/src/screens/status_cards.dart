import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/icon_num.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// `2026-09` as `09 · 2026`; anything else as it came.
String monthNumeral(String month) {
  final parts = month.split('-');
  return parts.length == 2 ? '${parts[1]} · ${parts[0]}' : month;
}

/// The lock as a glyph: red and closed while the PC is locked, green and
/// open when it is not. [reason] (the PC's sentence) is only spoken.
class LockMark extends StatelessWidget {
  /// Creates the mark.
  const new({required this.locked, required this.reason, super.key});

  /// Whether the PC is locked.
  final bool locked;

  /// The PC's own explanation; never painted.
  final String reason;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    return Icon(
      locked ? Icons.lock : Icons.lock_open,
      size: 36,
      color: locked ? colors.danger : colors.success,
      semanticLabel: reason,
    );
  }
}

/// The month's pace, or today's number when the PC asks one a day.
class PaceCard extends StatelessWidget {
  /// Creates the card for [pace].
  const new({required this.pace, super.key});

  /// The PC's pace position.
  final Pace pace;

  @override
  Widget build(BuildContext context) {
    final asks = pace.todayRequired;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pace.daily && asks != null)
              ..._day(context, asks)
            else
              ..._month(context),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                if (pace.excused > 0)
                  IconNum(
                    sickGlyph,
                    '${pace.excused}',
                    semanticLabel: 'sick days excused',
                  ),
                if (pace.carriedDebt > 0)
                  IconNum(
                    Icons.history,
                    '${pace.carriedDebt}',
                    semanticLabel: 'carried from last month',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The month: pages against the target, and the line today.
  List<Widget> _month(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.statusColors;
    final behind = pace.behind > 0;
    return [
      IconNum(Icons.calendar_month, monthNumeral(pace.month)),
      const SizedBox(height: AppSpacing.sm),
      IconNum(
        pagesGlyph,
        '${pace.pages} / ${pace.target}',
        style: theme.textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      LinearProgressIndicator(
        value: pace.target == 0
            ? 0.0
            : (pace.pages / pace.target).clamp(0.0, 1.0),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.md,
        children: [
          if (behind)
            IconNum(
              Icons.trending_down,
              '${pace.behind}',
              tint: colors.danger,
              semanticLabel: 'pages behind',
            )
          else
            Icon(
              Icons.check_circle,
              color: colors.success,
              semanticLabel: 'on pace',
            ),
          IconNum(
            targetGlyph,
            '${pace.required}',
            semanticLabel: "today's line",
          ),
        ],
      ),
    ];
  }

  /// One number a day: today's pages against it first, the month after.
  List<Widget> _day(BuildContext context, int asks) {
    final theme = Theme.of(context);
    final colors = context.statusColors;
    final read = pace.pagesToday;
    final met = pace.bonusToday || read >= asks;
    // A sick day asks nothing; its requirement still earns the hour.
    final sick = pace.todayQuota == 0 && asks > 0;
    return [
      Row(
        children: [
          Expanded(
            child: IconNum(
              Icons.today,
              '$read / $asks',
              style: theme.textTheme.headlineSmall,
            ),
          ),
          IconNum(
            bonusGlyph,
            '+1',
            tint: met ? colors.success : theme.hintColor,
            semanticLabel: 'one hour earned',
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      LinearProgressIndicator(
        value: asks == 0 ? 1.0 : (read / asks).clamp(0.0, 1.0),
        color: met ? colors.success : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          if (sick)
            Icon(sickGlyph, color: colors.warning, semanticLabel: 'sick day'),
          if (met)
            Icon(
              Icons.check_circle,
              color: colors.success,
              semanticLabel: 'met',
            )
          else
            IconNum(
              pagesGlyph,
              '${asks - read}',
              tint: colors.warning,
              semanticLabel: 'pages still to read',
            ),
          IconNum(Icons.calendar_month, monthNumeral(pace.month)),
          IconNum(pagesGlyph, '${pace.pages} / ${pace.target}'),
        ],
      ),
    ];
  }
}
