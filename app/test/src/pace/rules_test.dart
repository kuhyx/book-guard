import 'package:book_guard_app/src/pace/rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pace_inputs.dart';

void main() {
  group('days', () {
    test('parse, format and step', () {
      expect(parseDay('2026-10-15'), utcDay(2026, 10, 15));
      expect(isoDay(utcDay(2026, 1, 5)), '2026-01-05');
      expect(isoDay(addDays(utcDay(2026, 10, 31), 1)), '2026-11-01');
      expect(isoDay(addDays(utcDay(2026, 3, 1), -1)), '2026-02-28');
    });

    test('malformed days are null', () {
      expect(parseDay('2026-10'), isNull);
      expect(parseDay('2026-10-15-1'), isNull);
      expect(parseDay('2026-xx-15'), isNull);
      expect(parseDay('2026-10-'), isNull);
      expect(parseDay(''), isNull);
    });

    test('weekdays follow Python: Monday is 0', () {
      expect(pyWeekday(utcDay(2026, 10, 12)), 0);
      expect(pyWeekday(utcDay(2026, 10, 18)), 6);
    });

    test('month helpers', () {
      expect(monthStart(utcDay(2026, 10, 15)), utcDay(2026, 10, 1));
      expect(nextMonth(utcDay(2026, 12, 1)), utcDay(2027, 1, 1));
      expect(daySpan(utcDay(2026, 10, 3), utcDay(2026, 10, 5)).length, 3);
      expect(daySpan(utcDay(2026, 10, 5), utcDay(2026, 10, 3)), isEmpty);
      expect(monthDays(utcDay(2027, 2, 9)).length, 28);
      expect(monthDays(utcDay(2026, 12, 31)).last, utcDay(2026, 12, 31));
    });
  });

  group('PlanRules.fromJson', () {
    test('parses the golden constants', () {
      final r = rules();
      expect(r.paceStart, utcDay(2026, 10, 2));
      expect(r.quotaSwitch, utcDay(2026, 10, 12));
      expect(r.monthlyPages, 1000);
      expect(r.workdays, {1, 2, 3});
      expect(r.weekendCap, 60);
    });

    test('the resplit defaults to the constant, a sent one wins', () {
      expect(rules().resplit, utcDay(2026, 10, 18));
      final older = rulesJson()..remove('resplit');
      expect(PlanRules.fromJson(older)?.resplit, defaultResplit);
      final sent = {...rulesJson(), 'resplit': '2026-11-02'};
      expect(PlanRules.fromJson(sent)?.resplit, utcDay(2026, 11, 2));
      final broken = {...rulesJson(), 'resplit': 'oops'};
      expect(PlanRules.fromJson(broken), isNull);
    });

    test('anything missing or mistyped is null', () {
      // An older PC sends no resplit: that one falls back to the default.
      for (final key in rulesJson().keys.where((k) => k != 'resplit')) {
        final missing = rulesJson()..remove(key);
        expect(PlanRules.fromJson(missing), isNull, reason: 'no $key');
      }
      for (final key in const [
        'pace_start',
        'monthly_goal_start',
        'quota_switch',
        'monthly_pages',
        'weekend_days',
      ]) {
        final broken = {...rulesJson(), key: 'oops'};
        expect(PlanRules.fromJson(broken), isNull, reason: 'bad $key');
      }
    });

    test('non-integer weekdays are dropped from a list', () {
      final r = rules({
        'workdays': [1, 'x', 2],
      });
      expect(r.workdays, {1, 2});
    });
  });

  group('classes of days', () {
    final r = rules();
    final mon = utcDay(2026, 10, 12);
    final tue = utcDay(2026, 10, 13);
    final sat = utcDay(2026, 10, 17);

    test('weekend, workday and weights', () {
      expect(r.isWeekend(sat), isTrue);
      expect(r.isWeekend(tue), isFalse);
      expect(r.isWorkday(tue), isTrue);
      expect(r.isWorkday(mon), isFalse);
      expect(r.weight(sat), 50);
      expect(r.weight(tue), 15);
      expect(r.weight(mon), 30);
    });
  });
}
