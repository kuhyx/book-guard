/// Port of `book_guard/_plan.py`: one month's plan and where surplus goes.
///
/// Before the switch: the 20:40 weights, surplus off workdays then Fri-Mon.
/// From it: 15:30:50 with weekends capped, surplus off Mon-Fri. The switch
/// month walks the old rules up to the switch and re-splits the rest.
/// A sick day keeps its weight and its place in every cut but asks nothing:
/// its quota after the moves goes to [MonthPlan.excused], never re-split.
library;

import 'package:book_guard_app/src/pace/quotas.dart';
import 'package:book_guard_app/src/pace/rational.dart';
import 'package:book_guard_app/src/pace/rules.dart';

/// The plan as of some day.
class MonthPlan {
  /// Creates a plan.
  new(this.quotas, {Rational? leftover, Rational? unspread})
    : leftover = leftover ?? Rational.zero,
      unspread = unspread ?? Rational.zero;

  /// Each counted day's quota after the moves.
  final Quotas quotas;

  /// Surplus moved onto the day it was earned.
  final Quotas extra = {};

  /// What no remaining day could absorb.
  Rational leftover;

  /// Debt in a month with no counted day.
  Rational unspread;

  /// Sick days' quotas after the moves: off the line and the target.
  final Quotas excused = {};

  /// Pages the plan expects by the start of [day].
  Rational lineBefore(DateTime day) =>
      sumQ([
        for (final e in quotas.entries)
          if (e.key.isBefore(day)) e.value,
      ]) +
      sumQ([
        for (final e in extra.entries)
          if (e.key.isBefore(day)) e.value,
      ]);

  /// The month's requirement after carried credit came off it.
  Rational get target => sumQ(quotas.values) + sumQ(extra.values) + unspread;
}

/// Everything one month's plan is derived from (`_plan.MonthInput`).
class MonthInput {
  /// Creates an input.
  const new({
    required this.days,
    required this.counted,
    required this.weights,
    required this.target,
    required this.credit,
    required this.pagesOn,
    this.sick = const {},
  });

  /// Every day of the month.
  final List<DateTime> days;

  /// The paced, non-free days.
  final List<DateTime> counted;

  /// Each counted day's old-rule share of the base.
  final Quotas weights;

  /// Base plus carried debt.
  final int target;

  /// Surplus carried in.
  final Rational credit;

  /// Pages credited per day.
  final Map<DateTime, int> pagesOn;

  /// Sick days: counted, but no quota of their own.
  final Set<DateTime> sick;
}

typedef _Cut = Rational Function(Quotas, List<DateTime>, Rational);

/// The old rule's cut: workdays evenly first, then the rest.
Rational spreadCut(
  PlanRules rules,
  Quotas quotas,
  List<DateTime> days,
  Rational amount,
) {
  var taken = Rational.zero;
  for (final light in const [true, false]) {
    final pool = days.where((d) => rules.isWorkday(d) == light).toList();
    taken += drain(quotas, pool, amount - taken);
  }
  return taken;
}

MonthPlan _opening(MonthInput m, PlanRules rules) {
  final total = sumQ([for (final d in m.counted) m.weights[d]!]);
  if (total.isZero) {
    return MonthPlan({}, leftover: m.credit, unspread: Rational.of(m.target));
  }
  final debt = (Rational.of(m.target) - total) / Rational.of(m.counted.length);
  final quotas = {for (final d in m.counted) d: m.weights[d]! + debt};
  final taken = spreadCut(rules, quotas, m.counted, m.credit);
  return MonthPlan(quotas, leftover: m.credit - taken);
}

MonthPlan _weekdayOpening(MonthInput m, PlanRules rules) {
  final net = Rational.of(m.target) - m.credit;
  final (quotas, unspread) = split(rules, maxQ(net, Rational.zero), m.counted);
  return MonthPlan(
    quotas,
    leftover: maxQ(-net, Rational.zero),
    unspread: unspread,
  );
}

void _resplit(MonthPlan plan, MonthInput m, PlanRules rules) {
  final rest = m.counted.where((d) => !d.isBefore(rules.quotaSwitch)).toList();
  final (quotas, unspread) = split(
    rules,
    sumQ([for (final d in rest) plan.quotas[d]!]),
    rest,
  );
  plan.quotas.addAll(quotas);
  plan.unspread += unspread;
}

Rational _walk(
  MonthPlan plan,
  MonthInput m,
  List<DateTime> days,
  _Cut cut,
  Rational start,
) {
  var ahead = start;
  for (final day in days) {
    final planned = m.sick.contains(day)
        ? Rational.zero
        : plan.quotas[day] ?? Rational.zero;
    ahead += Rational.of(m.pagesOn[day] ?? 0) - planned;
    if (ahead <= Rational.zero) continue;
    final later = m.counted.where((d) => d.isAfter(day)).toList();
    final moved = cut(plan.quotas, later, ahead);
    if (!moved.isZero) {
      plan.extra[day] = moved;
      ahead -= moved;
    }
  }
  return ahead;
}

/// Walk [m] through [until] (inclusive), moving every surplus; [useSwitch]
/// applies the rules' switch (false: old rules only).
MonthPlan planMonth(
  MonthInput m,
  DateTime until,
  PlanRules rules, {
  required bool useSwitch,
}) {
  final known = m.days.where((d) => !d.isAfter(until)).toList();
  final change = rules.quotaSwitch;
  Rational newCut(Quotas q, List<DateTime> d, Rational a) =>
      cutWeekdays(rules, q, d, a);
  Rational oldCut(Quotas q, List<DateTime> d, Rational a) =>
      spreadCut(rules, q, d, a);
  late final MonthPlan plan;
  late Rational ahead;
  if (useSwitch && !change.isAfter(m.days.first)) {
    plan = _weekdayOpening(m, rules);
    ahead = _walk(plan, m, known, newCut, Rational.zero);
  } else {
    plan = _opening(m, rules);
    final old = known.where((d) => !useSwitch || d.isBefore(change)).toList();
    ahead = _walk(plan, m, old, oldCut, Rational.zero);
    if (useSwitch && m.days.contains(change)) {
      _resplit(plan, m, rules);
      final later = known.where((d) => !d.isBefore(change)).toList();
      ahead = _walk(plan, m, later, newCut, ahead);
    }
  }
  plan.leftover += maxQ(ahead, Rational.zero);
  for (final d in m.sick) {
    final quota = plan.quotas.remove(d);
    if (quota != null) plan.excused[d] = quota;
  }
  return plan;
}

/// What [day] asks: its quota after the moves, plus its weekend debt share.
Rational dayRequirement(
  MonthPlan plan,
  MonthInput m,
  DateTime day,
  PlanRules rules,
) {
  final quota = plan.quotas[day];
  if (quota == null) return Rational.zero;
  if (!rules.isWeekend(day)) return quota;
  final weekends = m.counted
      .where(
        (d) => !d.isBefore(day) && rules.isWeekend(d) && !m.sick.contains(d),
      )
      .toList();
  final (shares, _) = fillWeekends(
    rules,
    plan.quotas,
    weekends,
    debtAt(plan, m, day),
  );
  return quota + shares[day]!;
}

/// Pages behind the line at the start of [day] (0 when on pace).
Rational debtAt(MonthPlan plan, MonthInput m, DateTime day) {
  final read = m.pagesOn.entries
      .where((e) => e.key.isBefore(day))
      .fold(0, (sum, e) => sum + e.value);
  return maxQ(plan.lineBefore(day) - Rational.of(read), Rational.zero);
}
