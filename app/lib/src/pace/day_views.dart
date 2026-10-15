/// Port of `book_guard/_pace_view.py`: any day, past, today or projected.
///
/// Past day: the credits dated before it only. Today: live. Future day:
/// every day from today on meets its requirement exactly (today topped up,
/// never below what is credited), with one optional `±N` deviation; one
/// forward walk adds each assumed day to a copy of the credits.
library;

import 'dart:math' as math;

import 'package:book_guard_app/src/pace/month_pace.dart';
import 'package:book_guard_app/src/pace/rules.dart';

export 'package:book_guard_app/src/pace/month_pace.dart' show DayPace;
export 'package:book_guard_app/src/pace/rules.dart';

/// What a day before the switch asked (Q16; `_pace_text.OLD_RULE`).
const oldRuleText = 'Old rule: 15 pages + 15 min (10 + 10 when on pace)';

/// Which side of today a view is on.
enum DayKind {
  /// Before today: as it stood that morning.
  past,

  /// Today, live.
  today,

  /// After today: projected.
  future,
}

/// `state.json`'s `pace_inputs`: what any day is computed from.
class PaceInputs {
  /// Creates inputs.
  const new({
    required this.today,
    required this.rules,
    required this.credits,
    required this.freeDays,
  });

  /// Parses `pace_inputs`; null from a PC that predates it.
  static PaceInputs? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final today = parseDay('${json['today'] ?? ''}');
    final rules = json['rules'] is Map<String, dynamic>
        ? PlanRules.fromJson(json['rules'] as Map<String, dynamic>)
        : null;
    if (today == null || rules == null) return null;
    final credits = <DateTime, int>{};
    final raw = json['credits'];
    if (raw is Map<String, dynamic>) {
      for (final MapEntry(:key, :value) in raw.entries) {
        final day = parseDay(key);
        if (day != null && value is int) credits[day] = value;
      }
    }
    return PaceInputs(
      today: today,
      rules: rules,
      credits: credits,
      freeDays: {
        for (final d in json['free_days'] as List? ?? const []) ?parseDay('$d'),
      },
    );
  }

  /// The PC's today when it wrote these.
  final DateTime today;

  /// The plan's constants.
  final PlanRules rules;

  /// Pages credited per day.
  final Map<DateTime, int> credits;

  /// Declared free days.
  final Set<DateTime> freeDays;
}

/// One deviation: `delta` pages more (or fewer) than assumed on `day`.
typedef PaceSimulation = ({DateTime day, int delta});

/// One day's position.
class DayView {
  /// Creates a view.
  const new({
    required this.day,
    required this.kind,
    required this.pace,
    required this.credited,
    required this.assumed,
    required this.free,
    required this.oldRule,
    required this.beforeQuotas,
    this.simulated = 0,
  });

  /// The day.
  final DateTime day;

  /// Past, today or future.
  final DayKind kind;

  /// Its month's position computed for that day.
  final DayPace pace;

  /// Pages really credited that day (0 on a future day).
  final int credited;

  /// Pages the projection counts that day.
  final int assumed;

  /// A declared free day.
  final bool free;

  /// Before the switch: no daily requirement, the old bonus rule.
  final bool oldRule;

  /// Before the first quota day.
  final bool beforeQuotas;

  /// The simulation's delta when it falls on this day.
  final int simulated;

  /// The day's requirement.
  int get required => pace.required;
}

/// Each of [days] (ascending) as past, today or projected.
List<DayView> dayViews(
  PaceInputs inputs,
  List<DateTime> days, {
  PaceSimulation? sim,
}) {
  final PaceInputs(:today, :rules, :credits, :freeDays) = inputs;
  bool isFree(DateTime d) => freeDays.contains(d);
  DayView view(DayKind kind, DayPace pace, DateTime d, int got, int assumed) =>
      DayView(
        day: d,
        kind: kind,
        pace: pace,
        credited: got,
        assumed: assumed,
        free: isFree(d),
        oldRule: d.isBefore(rules.quotaSwitch),
        beforeQuotas: d.isBefore(rules.paceStart),
        simulated: sim != null && sim.day == d ? sim.delta : 0,
      );
  final out = <DayView>[];
  for (final d in days.where((d) => d.isBefore(today))) {
    final before = {
      for (final e in credits.entries)
        if (e.key.isBefore(d)) e.key: e.value,
    };
    final got = credits[d] ?? 0;
    out.add(
      view(DayKind.past, computePace(rules, before, d, isFree), d, got, got),
    );
  }
  if (days.isEmpty || days.last.isBefore(today)) return out;
  final wanted = days.toSet();
  final rows = {
    for (final e in credits.entries)
      if (!e.key.isAfter(today)) e.key: e.value,
  };
  for (final d in daySpan(today, days.last)) {
    final pace = computePace(rules, rows, d, isFree);
    final real = d == today ? credits[d] ?? 0 : 0;
    final delta = sim != null && sim.day == d ? sim.delta : 0;
    final assumed = math.max(math.max(real, pace.required) + delta, 0);
    if (assumed != real) rows[d] = assumed;
    if (wanted.contains(d)) {
      final kind = d == today ? DayKind.today : DayKind.future;
      out.add(view(kind, pace, d, real, assumed));
    }
  }
  return out;
}

/// Mon-Sun around [day].
List<DateTime> weekOf(DateTime day) {
  final monday = addDays(day, -pyWeekday(day));
  return daySpan(monday, addDays(monday, 6));
}
