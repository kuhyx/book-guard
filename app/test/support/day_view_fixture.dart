/// A [DayView] with sensible defaults, for the pace-cell widget tests.
library;

import 'package:book_guard_app/src/pace/day_views.dart';

/// A past, met day (22 of 17 pages) on 2026-10-15; override what a test
/// cares about.
DayView view({
  DayKind kind = DayKind.past,
  int credited = 22,
  int required = 17,
  int assumed = 22,
  bool free = false,
  bool sick = false,
  bool oldRule = false,
  bool beforeQuotas = false,
  int simulated = 0,
  int line = 100,
  int pages = 60,
  int debt = 0,
  int credit = 0,
}) => DayView(
  day: DateTime.utc(2026, 10, 15),
  kind: kind,
  pace: DayPace(
    month: DateTime.utc(2026, 10),
    target: 1000,
    carriedDebt: debt,
    carriedCredit: credit,
    pages: pages,
    line: line,
    required: required,
  ),
  credited: credited,
  assumed: assumed,
  free: free,
  sick: sick,
  oldRule: oldRule,
  beforeQuotas: beforeQuotas,
  simulated: simulated,
);
