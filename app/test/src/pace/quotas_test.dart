import 'package:book_guard_app/src/pace/quotas.dart';
import 'package:book_guard_app/src/pace/rational.dart';
import 'package:book_guard_app/src/pace/rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pace_inputs.dart';
import '../../support/rational_matchers.dart';

Rational q(int n) => Rational.of(n);

void main() {
  final r = rules();
  // Mon 12 .. Sun 18 October 2026.
  final week = daySpan(utcDay(2026, 10, 12), utcDay(2026, 10, 18));

  group('split', () {
    test('by weight when the weekend stays under the cap', () {
      // 15+30+...: Mon 30, Tue-Thu 15 x3, Fri 30, Sat/Sun 50 x2 = 205 units.
      final (quotas, rest) = split(r, q(205), week);
      expect(rest.isZero, isTrue);
      expect(quotas[utcDay(2026, 10, 12)], eq(30));
      expect(quotas[utcDay(2026, 10, 13)], eq(15));
      expect(quotas[utcDay(2026, 10, 17)], eq(50));
    });

    test('weekends are capped and the rest goes to the weekdays', () {
      final (quotas, rest) = split(r, q(410), week);
      expect(rest.isZero, isTrue);
      expect(quotas[utcDay(2026, 10, 17)], eq(60));
      expect(quotas[utcDay(2026, 10, 18)], eq(60));
      // 410 - 120 = 290 over 105 weekday units.
      expect(quotas[utcDay(2026, 10, 13)], eq(290 * 15, 105));
    });

    test('no counted day leaves the whole total unplaced', () {
      final (quotas, rest) = split(r, q(100), const []);
      expect(quotas, isEmpty);
      expect(rest, eq(100));
    });

    test(
      'weekends only: the capped weekends keep it, the rest is unplaced',
      () {
        final weekend = [utcDay(2026, 10, 17), utcDay(2026, 10, 18)];
        final (quotas, rest) = split(r, q(200), weekend);
        expect(quotas.values, everyElement(eq(60)));
        expect(rest, eq(80));
      },
    );
  });

  group('drain', () {
    test('takes evenly, smallest quota first', () {
      final days = week.take(3).toList();
      final quotas = {days[0]: q(2), days[1]: q(10), days[2]: q(10)};
      final taken = drain(quotas, days, q(12));
      expect(taken, eq(12));
      expect(quotas[days[0]], eq(0));
      expect(quotas[days[1]], eq(5));
      expect(quotas[days[2]], eq(5));
    });

    test('stops when the pool is empty', () {
      final days = week.take(2).toList();
      final quotas = {days[0]: q(1), days[1]: q(0)};
      expect(drain(quotas, days, q(5)), eq(1));
      expect(drain(quotas, days, q(5)).isZero, isTrue);
    });
  });

  group('cutWeekdays / fillWeekends', () {
    test('a weekday cut leaves the weekend alone', () {
      final quotas = {for (final d in week) d: q(10)};
      final taken = cutWeekdays(r, quotas, week, q(25));
      expect(taken, eq(25));
      expect(quotas[utcDay(2026, 10, 17)], eq(10));
      expect(quotas[utcDay(2026, 10, 12)], eq(5));
    });

    test('debt fills each weekend day up to the cap', () {
      final quotas = {utcDay(2026, 10, 17): q(50), utcDay(2026, 10, 18): q(40)};
      final (shares, unplaced) = fillWeekends(r, quotas, week, q(40));
      expect(shares[utcDay(2026, 10, 17)], eq(10));
      expect(shares[utcDay(2026, 10, 18)], eq(20));
      expect(unplaced, eq(10));
      expect(quotas[utcDay(2026, 10, 17)], eq(50), reason: 'not changed');
    });

    test('a weekend day with no quota has the whole cap free', () {
      final (shares, unplaced) = fillWeekends(r, {}, week, q(30));
      expect(shares[utcDay(2026, 10, 17)], eq(15));
      expect(unplaced.isZero, isTrue);
    });
  });
}
