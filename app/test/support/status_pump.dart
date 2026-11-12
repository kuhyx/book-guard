import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';

/// Pumps the Status tab on a phone-tall surface.
Future<void> pumpStatus(
  WidgetTester tester, {
  GuardState? state,
  Object? error,
  int waiting = 0,
}) {
  tallPhone(tester);
  return pumpTab(
    tester,
    StatusTab(state: state, error: error, waiting: waiting),
  );
}

/// A phone-tall surface, so every tile is on the first page.
void tallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(800, 1800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
