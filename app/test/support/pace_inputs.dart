import 'dart:convert';
import 'dart:io';

import 'package:book_guard_app/src/pace/day_views.dart';

/// The plan's constants as the PC sends them (the goldens' `rules`).
Map<String, dynamic> rulesJson() =>
    (jsonDecode(File('test/fixtures/pace_goldens.json').readAsStringSync())
            as Map<String, dynamic>)['rules']
        as Map<String, dynamic>;

/// The golden constants, parsed, with [overrides] on top of the JSON.
PlanRules rules([Map<String, dynamic> overrides = const {}]) =>
    PlanRules.fromJson({...rulesJson(), ...overrides})!;

/// `pace_inputs` as the PC writes it, with [rulesOverrides] applied.
Map<String, dynamic> inputsJson({
  String today = '2026-10-15',
  Map<String, int> credits = const {},
  List<String> freeDays = const [],
  Map<String, dynamic> rulesOverrides = const {},
}) => {
  'today': today,
  'rules': {...rulesJson(), ...rulesOverrides},
  'credits': credits,
  'free_days': freeDays,
};

/// Parsed `pace_inputs`.
PaceInputs inputs({
  String today = '2026-10-15',
  Map<String, int> credits = const {},
  List<String> freeDays = const [],
  Map<String, dynamic> rulesOverrides = const {},
}) => PaceInputs.fromJson(
  inputsJson(
    today: today,
    credits: credits,
    freeDays: freeDays,
    rulesOverrides: rulesOverrides,
  ),
)!;
