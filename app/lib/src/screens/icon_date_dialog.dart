import 'package:book_guard_app/src/screens/picker_parts.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// [moment]'s calendar day as a UTC midnight, so days compare by y/m/d
/// whether the caller passed UTC days (the pace panel) or local ones.
DateTime _dayOf(DateTime moment) =>
    DateTime.utc(moment.year, moment.month, moment.day);

/// A month grid with no words: `2026 · 11` and chevrons on top, Monday
/// first, Sat/Sun columns tinted, days outside `first`..`last` dimmed.
/// A tap selects a day; the check icon returns it, the close icon nothing.
class IconDateDialog extends StatefulWidget {
  /// Creates the dialog opened on [initial].
  const new({
    required this.initial,
    required this.first,
    required this.last,
    super.key,
  });

  /// The day selected when it opens.
  final DateTime initial;

  /// The first day that can be picked.
  final DateTime first;

  /// The last day that can be picked.
  final DateTime last;

  /// The largest a day's square gets; a narrow screen shrinks it.
  static const double cell = 40;

  @override
  State<IconDateDialog> createState() => _IconDateDialogState();
}

class _IconDateDialogState extends State<IconDateDialog> {
  late DateTime _picked = _dayOf(widget.initial);
  late DateTime _month = DateTime.utc(_picked.year, _picked.month);

  DateTime get _first => _dayOf(widget.first);
  DateTime get _last => _dayOf(widget.last);

  bool _canShow(DateTime month) =>
      !month.isBefore(DateTime.utc(_first.year, _first.month)) &&
      !month.isAfter(DateTime.utc(_last.year, _last.month));

  DateTime _shifted(int by) => DateTime.utc(_month.year, _month.month + by);

  void _confirm() =>
      Navigator.of(context)
          .pop(DateTime(_picked.year, _picked.month, _picked.day));

  Widget _chevron(int by, IconData icon, String spoken) {
    final to = _shifted(by);
    return IconButton(
      onPressed: _canShow(to) ? () => setState(() => _month = to) : null,
      icon: Icon(icon, semanticLabel: spoken),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = DateTime.utc(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[
      for (var i = 1; i < _month.weekday; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        _day(DateTime.utc(_month.year, _month.month, d)),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }
    final tint = Theme.of(context).colorScheme.primary.withValues(alpha: 0.1);
    // Seven squares in what the screen leaves after the dialog's inset and
    // padding (AlertDialog sizes intrinsically, so no LayoutBuilder here).
    final room = MediaQuery.sizeOf(context).width - AppSpacing.md * 4;
    final cell = (room / 7).clamp(0.0, IconDateDialog.cell);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      contentPadding: const EdgeInsets.all(AppSpacing.md),
      content: SizedBox(
        width: cell * 7,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _chevron(-1, Icons.chevron_left, 'Previous month'),
                Expanded(
                  child: Text(
                    '${_month.year} · ${pad2(_month.month)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _chevron(1, Icons.chevron_right, 'Next month'),
              ],
            ),
            for (var r = 0; r < cells.length; r += 7)
              Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Container(
                      width: cell,
                      height: cell,
                      color: c >= 5 ? tint : null,
                      child: cells[r + c],
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: pickerActions(context, _confirm),
    );
  }

  Widget _day(DateTime day) => PickerDay(
    day: day.day,
    enabled: !day.isBefore(_first) && !day.isAfter(_last),
    selected: day == _picked,
    onTap: () => setState(() => _picked = day),
  );
}

/// One day of the grid: its numeral, dimmed and inert outside the range.
class PickerDay extends StatelessWidget {
  /// Creates the square for day [day] of the month.
  const new({
    required this.day,
    required this.enabled,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// The day of the month.
  final int day;

  /// Whether it is inside `first`..`last` and can be tapped.
  final bool enabled;

  /// Whether it is the day the check icon would return.
  final bool selected;

  /// Selects it.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      customBorder: const CircleBorder(),
      child: Container(
        alignment: Alignment.center,
        decoration: selected
            ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
            : null,
        child: Text(
          '$day',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: selected
                ? scheme.onPrimary
                : enabled
                ? null
                : theme.disabledColor,
          ),
        ),
      ),
    );
  }
}
