import 'package:book_guard_app/src/pace/day_views.dart';
import 'package:book_guard_app/src/screens/pace_cells.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// This week, a month grid, any day, and a `±N` simulation -- all offline,
/// on the port of the PC's plan, from `state.json`'s `pace_inputs`.
///
/// Display only: a simulation never leaves this widget.
class PacePanel extends StatefulWidget {
  /// Creates the panel.
  const new({required this.inputs, super.key});

  /// What every day is computed from.
  final PaceInputs inputs;

  @override
  State<PacePanel> createState() => _PacePanelState();
}

class _PacePanelState extends State<PacePanel> {
  late DateTime _selected = widget.inputs.today;
  late DateTime _month = monthStart(widget.inputs.today);
  late DateTime _simDay = widget.inputs.today;
  int _delta = 0;

  static const _step = 5;

  PaceInputs get _inputs => widget.inputs;

  PaceSimulation? get _sim =>
      _delta == 0 ? null : (day: _simDay, delta: _delta);

  /// The range `pace_inputs` knows the free days of.
  DateTime get _first => monthStart(_inputs.rules.paceStart);
  DateTime get _last => utcDay(_inputs.today.year + 1, 12, 31);

  Future<DateTime?> _pick(DateTime initial, DateTime first) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: _last,
    );
    return picked == null
        ? null
        : utcDay(picked.year, picked.month, picked.day);
  }

  Future<void> _pickDay() async {
    final day = await _pick(_selected, _first);
    if (day != null && mounted) {
      setState(() {
        _selected = day;
        _month = monthStart(day);
      });
    }
  }

  Future<void> _pickSimDay() async {
    final day = await _pick(_simDay, _inputs.today);
    if (day != null && mounted) setState(() => _simDay = day);
  }

  void _select(DateTime day) => setState(() => _selected = day);

  void _shiftMonth(int by) =>
      setState(() => _month = DateTime.utc(_month.year, _month.month + by));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sim = _sim;
    final week = dayViews(_inputs, weekOf(_inputs.today), sim: sim);
    final month = dayViews(_inputs, monthDays(_month), sim: sim);
    final day = dayViews(_inputs, [_selected], sim: sim).single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sim != null)
          Text(
            'Simulation: ${_signed(sim.delta)} pages on ${shortDay(sim.day)} '
            '(display only)',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.statusColors.warning,
            ),
          ),
        const SectionHeader('This week'),
        Row(
          children: [
            for (final v in week)
              Expanded(
                child: DayCell(
                  view: v,
                  label: weekdayInitials[pyWeekday(v.day)],
                  selected: v.day == _selected,
                  onTap: () => _select(v.day),
                ),
              ),
          ],
        ),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: _month.isAfter(_first) ? () => _shiftMonth(-1) : null,
            ),
            Expanded(
              child: Text(
                monthTitle(_month),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: monthStart(_last).isAfter(_month)
                  ? () => _shiftMonth(1)
                  : null,
            ),
          ],
        ),
        Row(
          children: [
            for (final d in weekdayInitials)
              Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
        ..._grid(month),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDay,
                  icon: const Icon(Icons.calendar_today),
                  label: Text('Any day: ${shortDay(_selected)}'),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final line in dayLines(day)) Text(line),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Simulate', style: theme.textTheme.titleSmall),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  children: [
                    IconButton(
                      tooltip: '$_step pages fewer',
                      icon: const Icon(Icons.remove),
                      onPressed: () => setState(() => _delta -= _step),
                    ),
                    Text('${_signed(_delta)} pages'),
                    IconButton(
                      tooltip: '$_step pages more',
                      icon: const Icon(Icons.add),
                      onPressed: () => setState(() => _delta += _step),
                    ),
                    OutlinedButton(
                      onPressed: _pickSimDay,
                      child: Text('on ${shortDay(_simDay)}'),
                    ),
                    if (_delta != 0)
                      TextButton(
                        onPressed: () => setState(() => _delta = 0),
                        child: const Text('Reset'),
                      ),
                  ],
                ),
                Text(
                  'Later days follow the surplus and debt rules. Never saved.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The month as rows of 7, Monday first, blanks before the 1st.
  List<Widget> _grid(List<DayView> month) {
    final cells = <Widget>[
      for (var i = 0; i < pyWeekday(_month); i++) const SizedBox.shrink(),
      for (final v in month)
        DayCell(
          view: v,
          label: '${v.day.day}',
          selected: v.day == _selected,
          onTap: () => _select(v.day),
        ),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }
    return [
      for (var r = 0; r < cells.length; r += 7)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in cells.sublist(r, r + 7)) Expanded(child: c),
          ],
        ),
    ];
  }
}

String _signed(int n) => n > 0 ? '+$n' : '$n';
