// The zero-text guard's shared pieces: the whole home screen pumped over a
// fake PC, the pace sheet opener, and the text that is data, not UI.
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';
import 'finders_a.dart';
import 'library_api.dart';

/// Text the reader or the book wrote: shown as it is.
const content = [
  'Atomic Habits', 'James Clear', 'Done Book', 'Next Book', 'Wstep', //
  'Jeden', 'from the PC', 'first try', 'second try', 'mention the habit loop',
  'bookguard', 'https://old.host',
];

/// Pumps a fresh [HomeScreen] over a [FakeApi] holding [state].
Future<FakeApi> pumpHome(
  WidgetTester tester,
  GuardState? state, {
  bool desktop = false,
  ThemeData? theme,
  void Function(FakeApi api)? setUp,
}) async {
  tallSurface(tester);
  final api = FakeApi(state: state);
  setUp?.call(api);
  // A fresh HomeScreen: the previous one (and its state) must be gone.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? buildLightTheme(),
      home: HomeScreen(
        api: api,
        desktop: desktop,
        refreshEvery: const Duration(hours: 1),
      ),
    ),
  );
  await settle(tester);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  return api;
}

/// Opens the pace sheet, when the snapshot has one, so its cells are
/// checked too.
Future<void> openPaceSheet(WidgetTester tester) async {
  final details = iconLabeled('pace details');
  if (details.evaluate().isEmpty) return;
  await tester.tap(details);
  await tester.pumpAndSettle();
}
