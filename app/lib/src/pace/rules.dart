/// Days, and the plan's constants as the PC sends them (`pace_inputs.rules`).
///
/// Port of `book_guard/_constants.py` + `_quotas.py`'s weekday classes. Days
/// are UTC midnights so adding one never meets a DST hour; weekdays in the
/// rules are Python's (Mon 0 .. Sun 6), Dart's `weekday` is Mon 1 .. Sun 7.
library;

/// The UTC midnight of [y]-[m]-[d] (out-of-range days roll over).
DateTime utcDay(int y, int m, int d) => DateTime.utc(y, m, d);

/// [day] moved by [n] days.
DateTime addDays(DateTime day, int n) =>
    DateTime.utc(day.year, day.month, day.day + n);

/// `YYYY-MM-DD` as a day; null when malformed.
DateTime? parseDay(String text) {
  final parts = text.split('-');
  if (parts.length != 3) return null;
  final [y, m, d] = [for (final p in parts) int.tryParse(p)];
  if (y == null || m == null || d == null) return null;
  return utcDay(y, m, d);
}

/// [day] as `YYYY-MM-DD`.
String isoDay(DateTime day) => day.toIso8601String().substring(0, 10);

/// Python's `date.weekday()`: Mon 0 .. Sun 6.
int pyWeekday(DateTime day) => day.weekday - 1;

/// The first of [day]'s month.
DateTime monthStart(DateTime day) => DateTime.utc(day.year, day.month);

/// The first of the month after [first]'s.
DateTime nextMonth(DateTime first) => DateTime.utc(first.year, first.month + 1);

/// Every day from [first] to [last], both included.
List<DateTime> daySpan(DateTime first, DateTime last) => [
  for (var d = first; !d.isAfter(last); d = addDays(d, 1)) d,
];

/// Every day of [first]'s month.
List<DateTime> monthDays(DateTime first) =>
    daySpan(monthStart(first), addDays(nextMonth(monthStart(first)), -1));

/// The plan's constants.
class PlanRules {
  /// Creates the rules.
  const new({
    required this.paceStart,
    required this.monthlyGoalStart,
    required this.monthlyPages,
    required this.quotaSwitch,
    required this.workdayPages,
    required this.offdayPages,
    required this.workdays,
    required this.midweekDays,
    required this.weekendDays,
    required this.midweekWeight,
    required this.edgeWeight,
    required this.weekendWeight,
    required this.weekendCap,
  });

  /// Parses `pace_inputs.rules`; null when anything is missing.
  static PlanRules? fromJson(Map<String, dynamic> json) {
    DateTime? day(String key) => parseDay('${json[key] ?? ''}');
    int? whole(String key) => json[key] is int ? json[key] as int : null;
    Set<int>? days(String key) => json[key] is List
        ? {
            for (final d in json[key] as List)
              if (d is int) d,
          }
        : null;
    final (paceStart, goal, change) = (
      day('pace_start'),
      day('monthly_goal_start'),
      day('quota_switch'),
    );
    final numbers = [
      for (final k in const [
        'monthly_pages',
        'workday_pages',
        'offday_pages',
        'midweek_weight',
        'edge_weight',
        'weekend_weight',
        'weekend_cap',
      ])
        whole(k),
    ];
    final (work, mid, end) = (
      days('workdays'),
      days('midweek_days'),
      days('weekend_days'),
    );
    if (paceStart == null || goal == null || change == null) return null;
    if (work == null || mid == null || end == null || numbers.contains(null)) {
      return null;
    }
    final [monthly, workday, offday, midW, edgeW, endW, cap] = [
      for (final n in numbers) n!,
    ];
    return PlanRules(
      paceStart: paceStart,
      monthlyGoalStart: goal,
      monthlyPages: monthly,
      quotaSwitch: change,
      workdayPages: workday,
      offdayPages: offday,
      workdays: work,
      midweekDays: mid,
      weekendDays: end,
      midweekWeight: midW,
      edgeWeight: edgeW,
      weekendWeight: endW,
      weekendCap: cap,
    );
  }

  /// The first day with a page quota.
  final DateTime paceStart;

  /// The first month at [monthlyPages].
  final DateTime monthlyGoalStart;

  /// Each month's goal before the year's carry.
  final int monthlyPages;

  /// The first day of the 15:30:50 plan.
  final DateTime quotaSwitch;

  /// Before the switch: a workday's weight.
  final int workdayPages;

  /// Before the switch: a Fri-Mon day's weight.
  final int offdayPages;

  /// Before the switch: the light days (Python weekdays).
  final Set<int> workdays;

  /// Tue-Thu (Python weekdays).
  final Set<int> midweekDays;

  /// Sat, Sun (Python weekdays).
  final Set<int> weekendDays;

  /// From the switch: a Tue-Thu day's weight.
  final int midweekWeight;

  /// From the switch: a Mon/Fri day's weight.
  final int edgeWeight;

  /// From the switch: a Sat/Sun day's weight.
  final int weekendWeight;

  /// No Sat/Sun asks more than this.
  final int weekendCap;

  /// Sat or Sun.
  bool isWeekend(DateTime day) => weekendDays.contains(pyWeekday(day));

  /// Before the switch: a light day.
  bool isWorkday(DateTime day) => workdays.contains(pyWeekday(day));

  /// From the switch: a counted day's weight.
  int weight(DateTime day) => isWeekend(day)
      ? weekendWeight
      : midweekDays.contains(pyWeekday(day))
      ? midweekWeight
      : edgeWeight;
}
