/// Port of `book_guard/_resplit.py`: from the resplit, each morning splits
/// what is left of the month over the days left.
library;

import 'package:book_guard_app/src/pace/month_plan.dart';
import 'package:book_guard_app/src/pace/quotas.dart';
import 'package:book_guard_app/src/pace/rational.dart';
import 'package:book_guard_app/src/pace/rules.dart';

/// From [start] through [until]: each morning splits what is left.
///
/// What is left is the target net of carried credit, less the pages read
/// before that morning and the sick days excused so far; it is split by
/// weight over the counted days from that morning on (weekends capped), and
/// the morning's own share is the day's requirement. Each day then absorbs
/// its own deviation ([MonthPlan.extra]: read minus asked), so the line at
/// every morning is exactly the pages read. The days after [until] keep the
/// last morning's split. Mid-month the old plan's line meets the pages at
/// [start] the same way, on the day before it.
void resplitMornings(
  MonthPlan plan,
  MonthInput m,
  PlanRules rules,
  DateTime start,
  DateTime until,
) {
  plan.resplit = start;
  var read = m.pagesOn.entries
      .where((e) => e.key.isBefore(start))
      .fold(0, (sum, e) => sum + e.value);
  if (start != m.days.first) {
    final line = plan.lineBefore(start);
    final before = addDays(start, -1);
    plan.extra[before] =
        (plan.extra[before] ?? Rational.zero) + Rational.of(read) - line;
  }
  for (final later in [plan.quotas, plan.excused]) {
    later.removeWhere((d, _) => !d.isBefore(start));
  }
  var excused = sumQ(plan.excused.values);
  final net = Rational.of(m.target) - m.credit;
  var quotas = <DateTime, Rational>{};
  for (final day in daySpan(start, until).where(m.days.contains)) {
    final left = net - Rational.of(read) - excused;
    final rest = m.counted.where((d) => !d.isBefore(day)).toList();
    final (morning, unspread) = split(rules, maxQ(left, Rational.zero), rest);
    quotas = morning;
    plan
      ..unspread = unspread
      ..leftover = maxQ(-left, Rational.zero);
    var ask = quotas[day] ?? Rational.zero;
    if (m.sick.contains(day)) {
      plan.excused[day] = ask;
      excused += ask;
      ask = Rational.zero;
    } else if (quotas.containsKey(day)) {
      plan.quotas[day] = ask;
    }
    final pages = m.pagesOn[day] ?? 0;
    if (day.isBefore(until)) plan.extra[day] = Rational.of(pages) - ask;
    read += pages;
  }
  plan.quotas.addAll({
    for (final e in quotas.entries)
      if (e.key.isAfter(until)) e.key: e.value,
  });
}
