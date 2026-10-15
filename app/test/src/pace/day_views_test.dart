import 'package:book_guard_app/src/pace/day_views.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pace_inputs.dart';

DateTime d(int month, int day) => utcDay(2026, month, day);

void main() {
  group('PaceInputs.fromJson', () {
    test('parses today, rules, credits and free days', () {
      final i = inputs(
        credits: {'2026-10-03': 53},
        freeDays: ['2026-10-09', 'junk'],
      );
      expect(i.today, d(10, 15));
      expect(i.credits, {d(10, 3): 53});
      expect(i.freeDays, {d(10, 9)});
    });

    test('a PC that predates it, or garbage, is null', () {
      expect(PaceInputs.fromJson(null), isNull);
      expect(PaceInputs.fromJson('x'), isNull);
      expect(PaceInputs.fromJson({'today': '2026-10-15'}), isNull);
      expect(PaceInputs.fromJson({'today': 'x', 'rules': rulesJson()}), isNull);
      expect(
        PaceInputs.fromJson({'today': '2026-10-15', 'rules': 'x'}),
        isNull,
      );
      expect(
        PaceInputs.fromJson({
          'today': '2026-10-15',
          'rules': {'monthly_pages': 1},
        }),
        isNull,
      );
    });

    test('bad credits and a missing free-day list are skipped', () {
      final i = PaceInputs.fromJson({
        'today': '2026-10-15',
        'rules': rulesJson(),
        'credits': {'2026-10-03': 53, 'junk': 4, '2026-10-04': 'x'},
      })!;
      expect(i.credits, {d(10, 3): 53});
      expect(i.freeDays, isEmpty);
      final bare = PaceInputs.fromJson({
        'today': '2026-10-15',
        'rules': rulesJson(),
        'credits': 'x',
      })!;
      expect(bare.credits, isEmpty);
    });
  });

  group('dayViews', () {
    final i = inputs(credits: {'2026-10-13': 17});

    test('past, today and future are told apart', () {
      final views = dayViews(i, [d(10, 13), d(10, 15), d(10, 16)]);
      expect(views.map((v) => v.kind), [
        DayKind.past,
        DayKind.today,
        DayKind.future,
      ]);
      expect(views.first.credited, 17);
      expect(views.first.assumed, 17);
      expect(views.last.credited, 0);
      expect(views.last.assumed, views.last.required);
      expect(views.last.required, views.last.pace.required);
    });

    test('only the past: nothing is projected', () {
      final views = dayViews(i, [d(10, 13), d(10, 14)]);
      expect(views.length, 2);
      expect(views.every((v) => v.kind == DayKind.past), isTrue);
    });

    test('no days, no views', () {
      expect(dayViews(i, const []), isEmpty);
    });

    test('flags: before quotas, old rule, free', () {
      final views = dayViews(inputs(freeDays: ['2026-10-16']), [
        d(10, 1),
        d(10, 5),
        d(10, 16),
      ]);
      expect(views[0].beforeQuotas, isTrue);
      expect(views[0].oldRule, isTrue);
      expect(views[1].beforeQuotas, isFalse);
      expect(views[1].oldRule, isTrue);
      expect(views[2].oldRule, isFalse);
      expect(views[2].free, isTrue);
      expect(views[1].free, isFalse);
    });

    test('a simulation lands on its day only, and never below zero', () {
      final sim = (day: d(10, 16), delta: -500);
      final views = dayViews(i, [d(10, 15), d(10, 16), d(10, 17)], sim: sim);
      expect(views.map((v) => v.simulated), [0, -500, 0]);
      expect(views[1].assumed, 0);
      final plus = dayViews(i, [d(10, 15)], sim: (day: d(10, 15), delta: 40));
      expect(plus.single.assumed, plus.single.required + 40);
      expect(plus.single.simulated, 40);
    });

    test('today topped up never goes below what is credited', () {
      final done = inputs(credits: {'2026-10-15': 900});
      final today = dayViews(done, [d(10, 15)]).single;
      expect(today.credited, 900);
      expect(today.assumed, 900);
    });
  });

  test('weekOf is Monday to Sunday around the day', () {
    final week = weekOf(d(10, 15));
    expect(week.first, d(10, 12));
    expect(week.last, d(10, 18));
    expect(week.length, 7);
    expect(weekOf(d(10, 18)).first, d(10, 12));
  });
}
