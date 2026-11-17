import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';
import 'finders_read.dart';

final Finder _field = find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

/// Opens the review screen's keypad, types [page], sends it.
Future<void> typeOnKeypad(WidgetTester tester, int page) async {
  await tester.tap(spoken('Type the page number'));
  await settle(tester, 10);
  await tester.enterText(_field, '$page');
  await tester.tap(spoken('Send the typed page number'));
  await settle(tester, 10);
}

/// Taps [button] (a photo button on a tab with no reader), which asks for the
/// page number at once; types one and sends it.
Future<void> tapAndType(
  WidgetTester tester,
  Finder button, [
  int page = 7,
]) async {
  await tapVisible(tester, button);
  await settle(tester, 10);
  await tester.enterText(_field, '$page');
  await tester.tap(spoken('Send the typed page number'));
  await settle(tester);
}
