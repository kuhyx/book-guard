import 'package:book_guard_app/src/pace/day_views.dart';
import 'package:book_guard_app/src/screens/icon_num.dart';
import 'package:book_guard_app/src/screens/pace_cells.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Everything about one day (what `dayLines` used to say), as glyphs and
/// numbers: the day and which side of today it is on, what it asks and what
/// is credited, the simulated total, the line and the month's target.
class DayDetails extends StatelessWidget {
  /// Creates the details of [view].
  const new({required this.view, super.key});

  /// The day.
  final DayView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final p = v.pace;
    final colors = context.statusColors;
    final when = switch (v.kind) {
      DayKind.past => (Icons.history, 'as it stood that morning'),
      DayKind.today => (Icons.today, 'today, live'),
      DayKind.future => (Icons.double_arrow, 'projected'),
    };
    final head = Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconNum(Icons.calendar_today, shortDay(v.day)),
        Icon(when.$1, size: 20, semanticLabel: when.$2),
        if (v.free) Icon(freeGlyph, color: colors.info, semanticLabel: 'free'),
        if (v.sick)
          Icon(sickGlyph, color: colors.warning, semanticLabel: 'sick'),
      ],
    );
    if (v.beforeQuotas) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          head,
          Icon(
            Icons.block,
            color: Theme.of(context).hintColor,
            semanticLabel: 'no page quota yet',
          ),
        ],
      );
    }
    if (v.oldRule) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [head, IconNum(Icons.history, '${v.credited}')],
      );
    }
    final delta = '${v.simulated > 0 ? '+' : ''}${v.simulated}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        head,
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            if (!v.free && !v.sick)
              IconNum(
                pagesGlyph,
                v.kind == DayKind.future
                    ? '${v.required}'
                    : '${v.credited} / ${v.required}',
                semanticLabel: 'requirement',
              ),
            if (v.simulated != 0)
              IconNum(
                Icons.science,
                '${v.assumed} ($delta)',
                tint: colors.warning,
                semanticLabel: 'simulated',
              )
            else if (v.kind == DayKind.future)
              IconNum(
                Icons.timeline,
                '${v.assumed}',
                semanticLabel: 'assumed read',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            IconNum(
              Icons.trending_flat,
              '${p.line}',
              semanticLabel: 'line at the start of the day',
            ),
            IconNum(pagesGlyph, '${p.pages}', semanticLabel: 'read'),
            if (p.behind > 0)
              IconNum(
                Icons.trending_down,
                '${p.behind}',
                tint: colors.danger,
                semanticLabel: 'behind',
              )
            else
              Icon(
                Icons.check_circle,
                color: colors.success,
                semanticLabel: 'on pace',
              ),
            IconNum(targetGlyph, '${p.target}', semanticLabel: 'month target'),
            if (p.carriedDebt > 0)
              IconNum(
                Icons.history,
                '${p.carriedDebt}',
                tint: colors.danger,
                semanticLabel: 'carried debt',
              ),
            if (p.carriedCredit > 0)
              IconNum(
                Icons.add_circle_outline,
                '${p.carriedCredit}',
                tint: colors.success,
                semanticLabel: 'carried credit',
              ),
          ],
        ),
      ],
    );
  }
}
