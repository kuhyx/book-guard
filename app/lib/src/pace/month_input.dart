/// What one month's plan is derived from (port of `_plan.MonthInput`).
library;

import 'package:book_guard_app/src/pace/quotas.dart';
import 'package:book_guard_app/src/pace/rational.dart';

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
    this.eased = const {},
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

  /// Pages taken off a day's morning share from the resplit; the days left
  /// owe them (`_ease.eased_days`).
  final Map<DateTime, int> eased;
}
