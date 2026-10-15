import 'package:book_guard_app/src/pace/month_pace.dart';
import 'package:book_guard_app/src/pace/month_plan.dart';
import 'package:book_guard_app/src/pace/rational.dart';
import 'package:book_guard_app/src/pace/rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pace_inputs.dart';
import '../../support/rational_matchers.dart';

Rational q(int n) => Rational.of(n);

DateTime d(int month, int day) => utcDay(2026, month, day);

bool never(DateTime day) => false;

void main() {
  group('MonthPlan', () {
    test('line and target add the surplus moved onto a day', () {
      final plan = MonthPlan({d(11, 2): q(10), d(11, 3): q(20)});
      plan.extra[d(11, 2)] = q(5);
      expect(plan.lineBefore(d(11, 1)), eq(0));
      expect(plan.lineBefore(d(11, 3)), eq(15));
      expect(plan.lineBefore(d(11, 4)), eq(35));
      expect(plan.target, eq(35));
      expect(plan.leftover.isZero, isTrue);
    });

    test('unspread debt counts toward the target', () {
      final plan = MonthPlan({}, leftover: q(3), unspread: q(7));
      expect(plan.target, eq(7));
      expect(plan.leftover, eq(3));
    });
  });

  group('old rules (before the switch)', () {
    final old = rules({'quota_switch': '2027-06-01'});

    MonthInput month({
      Map<DateTime, int> pagesOn = const {},
      int target = 960,
      int credit = 0,
    }) {
      final days = monthDays(d(11, 1));
      return MonthInput(
        days: days,
        counted: days,
        weights: {
          for (final x in days)
            x: Rational.of(
              old.isWorkday(x) ? old.workdayPages : old.offdayPages,
            ),
        },
        target: target,
        credit: q(credit),
        pagesOn: pagesOn,
      );
    }

    test('weights plus the debt spread evenly', () {
      final plan = planMonth(
        month(target: 990),
        d(11, 30),
        old,
        useSwitch: false,
      );
      // 960 of weights, 30 of debt over 30 days: +1 each.
      expect(plan.quotas[d(11, 3)], eq(21));
      expect(plan.quotas[d(11, 1)], eq(41));
      expect(plan.target, eq(990));
    });

    test('carried credit comes off the workdays first', () {
      final plan = planMonth(
        month(credit: 60),
        d(11, 1),
        old,
        useSwitch: false,
      );
      // 60 pages over the 12 Tue-Thu days: 5 each.
      expect(plan.quotas[d(11, 3)], eq(15));
      expect(plan.quotas[d(11, 4)], eq(15));
      expect(plan.quotas[d(11, 1)], eq(40));
      expect(plan.leftover.isZero, isTrue);
    });

    test('a surplus moves onto the later days and is remembered', () {
      final plan = planMonth(
        month(pagesOn: {d(11, 1): 100}),
        d(11, 2),
        old,
        useSwitch: false,
      );
      // 100 read against a 40 quota: 60 off the days after the 1st.
      expect(plan.extra[d(11, 1)], eq(60));
      expect(plan.lineBefore(d(11, 2)), eq(100));
    });

    test('credit nobody can absorb is left over', () {
      final plan = planMonth(
        month(credit: 5000),
        d(11, 30),
        old,
        useSwitch: false,
      );
      expect(plan.leftover, eq(5000 - 960));
    });

    test('a month with no counted day keeps the target unspread', () {
      final empty = MonthInput(
        days: monthDays(d(11, 1)),
        counted: const [],
        weights: const {},
        target: 1000,
        credit: q(4),
        pagesOn: const {},
      );
      final plan = planMonth(empty, d(11, 30), old, useSwitch: false);
      expect(plan.unspread, eq(1000));
      expect(plan.leftover, eq(4));
      expect(plan.target, eq(1000));
    });

    test('dayRequirement is the quota; zero for a day off the plan', () {
      final input = month();
      final plan = planMonth(input, d(11, 30), old, useSwitch: false);
      expect(dayRequirement(plan, input, d(11, 3), old), eq(20));
      expect(dayRequirement(plan, input, d(10, 1), old).isZero, isTrue);
    });
  });

  group('new rules', () {
    final r = rules();

    test('a weekend asks its quota plus its share of the debt', () {
      final days = monthDays(d(11, 1));
      final input = MonthInput(
        days: days,
        counted: days,
        weights: const {},
        target: 1000,
        credit: Rational.zero,
        pagesOn: const {},
      );
      final plan = planMonth(input, d(11, 7), r, useSwitch: true);
      final sat = d(11, 7);
      // Nothing read: the debt at the start of Saturday is the line so far.
      expect(debtAt(plan, input, sat).compareTo(plan.lineBefore(sat)), 0);
      expect(
        dayRequirement(plan, input, sat, r).ceil(),
        greaterThanOrEqualTo(plan.quotas[sat]!.ceil()),
      );
      expect(debtAt(plan, input, d(11, 1)).isZero, isTrue);
    });

    test('debt is zero when the pages read exceed the line', () {
      final days = monthDays(d(11, 1));
      final input = MonthInput(
        days: days,
        counted: days,
        weights: const {},
        target: 1000,
        credit: Rational.zero,
        pagesOn: {d(11, 1): 5000},
      );
      final plan = planMonth(input, d(11, 5), r, useSwitch: true);
      expect(debtAt(plan, input, d(11, 5)).isZero, isTrue);
    });

    test('a negative net target leaves the credit unspent', () {
      final days = monthDays(d(11, 1));
      final input = MonthInput(
        days: days,
        counted: days,
        weights: const {},
        target: 100,
        credit: q(300),
        pagesOn: const {},
      );
      final plan = planMonth(input, d(11, 1), r, useSwitch: true);
      expect(plan.leftover, eq(200));
      expect(plan.target.isZero, isTrue);
    });
  });

  group('computePace', () {
    final r = rules();

    test(
      'the first month under the goal takes the old weights as its base',
      () {
        // October: 12 light days x 20 + 18 others x 40 = 960 against a 1000
        // goal; the goal only starts in November here.
        final late = rules({'monthly_goal_start': '2026-11-01'});
        final pace = computePace(late, {d(10, 5): 900}, d(11, 5), never);
        // Base 960, read 900: balance 60, over the 2 months left -> carry 30.
        expect(pace.carriedDebt, 30);
        expect(pace.target, 1030);
        expect(pace.month, d(11, 1));
      },
    );

    test('free days leave the old base of an earlier month', () {
      final late = rules({'monthly_goal_start': '2026-11-01'});
      bool free(DateTime day) => day.month == 10 && day.day > 2;
      // October then has only the 2nd (a Friday, 40), nothing read.
      final pace = computePace(late, const {}, d(11, 5), free);
      expect(pace.carriedDebt, 20);
    });

    test('pages read ahead carry over as credit', () {
      final pace = computePace(r, {d(10, 5): 1040}, d(11, 5), never);
      expect(pace.carriedCredit, 20);
      expect(pace.carriedDebt, 0);
      expect(pace.target, 980);
    });

    test('December carries into January whole', () {
      final pace = computePace(r, {d(12, 5): 940}, utcDay(2027, 1, 5), never);
      // Oct and Nov unread (-2000 + ...) are in the balance too; January
      // takes the whole of it, so the share equals the balance.
      expect(pace.carriedDebt, greaterThan(1000));
    });

    test('behind is how far under the line the month stands', () {
      final pace = computePace(r, const {}, d(10, 15), never);
      expect(pace.behind, pace.line - pace.pages);
      final ahead = computePace(r, {d(10, 2): 5000}, d(10, 15), never);
      expect(ahead.behind, 0);
    });

    test('a month of free days asks nothing and keeps the target', () {
      final pace = computePace(r, const {}, d(11, 10), (_) => true);
      expect(pace.required, 0);
      expect(pace.line, 0);
      expect(pace.target, 1500);
    });
  });
}
