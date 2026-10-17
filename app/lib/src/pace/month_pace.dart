/// Port of `book_guard/_pace.compute_pace`: the line and the year's carry.
///
/// Fed per-day credit sums instead of a ledger; everything else is the
/// Python's month loop: each past month's base minus its pages is the
/// balance, spread over the months left in the year (January takes all).
library;

import 'package:book_guard_app/src/pace/month_plan.dart';
import 'package:book_guard_app/src/pace/rational.dart';
import 'package:book_guard_app/src/pace/rules.dart';

/// Where a day's month stands (the numbers `pace_goldens.json` holds).
class DayPace {
  /// Creates a position.
  const new({
    required this.month,
    required this.target,
    required this.carriedDebt,
    required this.carriedCredit,
    required this.pages,
    required this.line,
    required this.required,
  });

  /// The first of the month.
  final DateTime month;

  /// The month's target after the carry.
  final int target;

  /// This month's share of the balance owed.
  final int carriedDebt;

  /// This month's share of the pages read ahead.
  final int carriedCredit;

  /// Pages credited in the month (in the credits given).
  final int pages;

  /// The pace line at the start of the day; from the resplit, at its end
  /// (the pages read before it plus the day's own number).
  final int line;

  /// The day's requirement (quota after moves plus weekend debt share).
  final int required;

  /// Pages short of the line.
  int get behind => line > pages ? line - pages : 0;
}

/// Python's `_months_left`: January takes December's whole balance.
int _monthsLeft(DateTime first) => first.month == 1 ? 1 : 13 - first.month;

/// Python's `_share`: rounded away from zero.
int _share(int balance, int months) {
  final share = (balance.abs() + months - 1) ~/ months;
  return balance >= 0 ? share : -share;
}

/// One month's plan through [until], and its input and base.
(MonthPlan, MonthInput, int) _plan(
  PlanRules rules,
  Map<DateTime, int> credits,
  DateTime first,
  bool Function(DateTime) isFree,
  Set<DateTime> sick,
  int carry,
  DateTime until,
) {
  final days = monthDays(first);
  final counted = [
    for (final d in days)
      if (!d.isBefore(rules.paceStart) && !isFree(d)) d,
  ];
  final quotas = {
    for (final d in counted)
      d: rules.isWorkday(d) ? rules.workdayPages : rules.offdayPages,
  };
  final total = quotas.values.fold(0, (a, b) => a + b);
  final base = first.isBefore(rules.monthlyGoalStart)
      ? total
      : rules.monthlyPages;
  final month = MonthInput(
    days: days,
    counted: counted,
    weights: {
      for (final e in quotas.entries)
        e.key: Rational.frac(e.value * base, total),
    },
    target: base + (carry > 0 ? carry : 0),
    credit: Rational.of(carry < 0 ? -carry : 0),
    pagesOn: {
      for (final e in credits.entries)
        if (e.key.year == first.year && e.key.month == first.month)
          e.key: e.value,
    },
    sick: sick,
  );
  final useSwitch = nextMonth(first).isAfter(rules.quotaSwitch);
  final useResplit = nextMonth(first).isAfter(rules.resplit);
  final plan = planMonth(
    month,
    until,
    rules,
    useSwitch: useSwitch,
    useResplit: useResplit,
  );
  return (plan, month, base);
}

/// The pace position for [today]'s month, from [credits] (pages per day).
DayPace computePace(
  PlanRules rules,
  Map<DateTime, int> credits,
  DateTime today,
  bool Function(DateTime) isFree, {
  Set<DateTime> sick = const {},
}) {
  final current = monthStart(today);
  var balance = 0;
  for (
    var first = monthStart(rules.paceStart);
    first.isBefore(current);
    first = nextMonth(first)
  ) {
    // The Python plans each past month too, but only its base and pages
    // reach the balance; the base needs no walk.
    final days = monthDays(first);
    final counted = days.where(
      (d) => !d.isBefore(rules.paceStart) && !isFree(d),
    );
    final base = first.isBefore(rules.monthlyGoalStart)
        ? counted.fold(
            0,
            (a, d) =>
                a +
                (rules.isWorkday(d) ? rules.workdayPages : rules.offdayPages),
          )
        : rules.monthlyPages;
    final read = credits.entries
        .where((e) => e.key.year == first.year && e.key.month == first.month)
        .fold(0, (a, e) => a + e.value);
    // A sick day's share is owed by nobody (Python: the month's plan).
    final owed = days.any(sick.contains)
        ? (Rational.of(base) -
                  sumQ(
                    _plan(
                      rules,
                      credits,
                      first,
                      isFree,
                      sick,
                      0,
                      days.last,
                    ).$1.excused.values,
                  ))
              .ceil()
        : base;
    balance += owed - read;
  }
  final carry = _share(balance, _monthsLeft(current));
  final (plan, month, _) = _plan(
    rules,
    credits,
    current,
    isFree,
    sick,
    carry,
    today,
  );
  final required = dayRequirement(plan, month, today, rules).ceil();
  final line = plan.lineBefore(today).ceil();
  return DayPace(
    month: current,
    target: plan.target.ceil(),
    carriedDebt: carry > 0 ? carry : 0,
    carriedCredit: carry < 0 ? -carry : 0,
    pages: month.pagesOn.values.fold(0, (a, b) => a + b),
    // From the resplit the line is the morning's plus the day's own number.
    line: today.isBefore(rules.resplit) ? line : line + required,
    required: required,
  );
}
