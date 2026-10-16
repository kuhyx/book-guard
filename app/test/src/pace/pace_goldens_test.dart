import 'dart:convert';
import 'dart:io';

import 'package:book_guard_app/src/pace/day_views.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every day of every case in `pace_goldens.json` (written by the Python
/// plan, `scripts/pace_goldens.py`) must come out of the Dart port equal.
void main() {
  final doc = jsonDecode(
    File('test/fixtures/pace_goldens.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final rules = doc['rules'] as Map<String, dynamic>;

  for (final raw in doc['cases'] as List) {
    final kase = raw as Map<String, dynamic>;
    test('${kase['name']}: every day matches the Python', () {
      final inputs = PaceInputs.fromJson({
        'today': kase['today'],
        'rules': rules,
        'credits': kase['credits'],
        'free_days': kase['free_days'],
        'sick_days': kase['sick_days'],
      })!;
      final simulate = kase['simulate'] as Map<String, dynamic>?;
      final sim = simulate == null
          ? null
          : (
              day: parseDay('${simulate['day']}')!,
              delta: simulate['delta'] as int,
            );
      final golden = kase['days'] as List;
      final views = dayViews(inputs, [
        for (final d in golden) parseDay('${(d as Map)['day']}')!,
      ], sim: sim);
      expect(views.length, golden.length);
      final mismatches = <String>[];
      for (var i = 0; i < views.length; i++) {
        final v = views[i];
        final want = golden[i] as Map<String, dynamic>;
        final got = {
          'day': isoDay(v.day),
          'kind': v.kind.name,
          'required': v.required,
          'credited': v.credited,
          'assumed': v.assumed,
          'line': v.pace.line,
          'target': v.pace.target,
          'month_pages': v.pace.pages,
          'behind': v.pace.behind,
          'carried_debt': v.pace.carriedDebt,
          'carried_credit': v.pace.carriedCredit,
          'free': v.free,
          'sick': v.sick,
          'old_rule': v.oldRule,
        };
        for (final key in got.keys) {
          if (got[key] != want[key]) {
            mismatches.add('${want['day']} $key: ${got[key]} != ${want[key]}');
          }
        }
      }
      expect(mismatches, isEmpty);
    });
  }
}
