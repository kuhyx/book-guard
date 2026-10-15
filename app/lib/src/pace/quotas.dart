/// Port of `book_guard/_quotas.py`: the split, the weekend cap, the moves.
///
/// Keep it line-for-line with the Python; `test/fixtures/pace_goldens.json`
/// (from `scripts/pace_goldens.py`) is the judge.
library;

import 'package:book_guard_app/src/pace/rational.dart';
import 'package:book_guard_app/src/pace/rules.dart';

/// Quotas per day.
typedef Quotas = Map<DateTime, Rational>;

/// [total] over [days] by weight, weekends capped; and what found no day.
(Quotas, Rational) split(PlanRules rules, Rational total, List<DateTime> days) {
  final units = days.fold(0, (sum, d) => sum + rules.weight(d));
  if (units == 0) return (<DateTime, Rational>{}, total);
  final scale = total / Rational.of(units);
  final weekends = days.where(rules.isWeekend).toList();
  if (scale * Rational.of(rules.weekendWeight) <=
      Rational.of(rules.weekendCap)) {
    return (
      {for (final d in days) d: Rational.of(rules.weight(d)) * scale},
      Rational.zero,
    );
  }
  final cap = Rational.of(rules.weekendCap);
  final quotas = <DateTime, Rational>{for (final d in weekends) d: cap};
  final rest = total - cap * Rational.of(weekends.length);
  final weekdays = days.where((d) => !rules.isWeekend(d)).toList();
  final weekUnits = weekdays.fold(0, (sum, d) => sum + rules.weight(d));
  if (weekUnits == 0) return (quotas, rest);
  for (final d in weekdays) {
    quotas[d] = Rational.of(rules.weight(d)) * rest / Rational.of(weekUnits);
  }
  return (quotas, Rational.zero);
}

/// Take up to [amount] off [pool] evenly (water-filling); return how much.
Rational drain(Quotas quotas, List<DateTime> pool, Rational amount) {
  var taken = Rational.zero;
  var left = [
    for (final d in pool)
      if (quotas[d]! > Rational.zero) d,
  ];
  while (taken < amount && left.isNotEmpty) {
    var cut = (amount - taken) / Rational.of(left.length);
    for (final d in left) {
      if (quotas[d]! < cut) cut = quotas[d]!;
    }
    for (final d in left) {
      quotas[d] = quotas[d]! - cut;
    }
    taken += cut * Rational.of(left.length);
    left = [
      for (final d in left)
        if (quotas[d]! > Rational.zero) d,
    ];
  }
  return taken;
}

/// Take up to [amount] off the Mon-Fri [days], evenly; weekends keep theirs.
Rational cutWeekdays(
  PlanRules rules,
  Quotas quotas,
  List<DateTime> days,
  Rational amount,
) => drain(quotas, days.where((d) => !rules.isWeekend(d)).toList(), amount);

/// [debt] over the weekend [days] evenly, each up to the cap: each weekend
/// day's share, and the part no weekend can hold. [quotas] is not changed.
(Quotas, Rational) fillWeekends(
  PlanRules rules,
  Quotas quotas,
  List<DateTime> days,
  Rational debt,
) {
  final cap = Rational.of(rules.weekendCap);
  final room = <DateTime, Rational>{
    for (final d in days.where(rules.isWeekend))
      d: maxQ(cap - (quotas[d] ?? Rational.zero), Rational.zero),
  };
  final left = Map.of(room);
  final placed = drain(left, room.keys.toList(), debt);
  return ({for (final d in room.keys) d: room[d]! - left[d]!}, debt - placed);
}
