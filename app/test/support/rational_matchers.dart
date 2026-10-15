import 'package:book_guard_app/src/pace/rational.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matches a [Rational] equal to `n / d` ([Rational] has no `==`).
Matcher eq(int n, [int d = 1]) => predicate<Rational>(
  (r) => r.compareTo(Rational.frac(n, d)) == 0,
  'equals $n/$d',
);
