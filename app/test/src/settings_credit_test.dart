import 'package:book_guard_app/src/login_store.dart';
import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:book_guard_app/src/screens/settings_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuhy_credit/kuhy_credit.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_api.dart';
import '../support/states.dart';

void main() {
  testWidgets('settings screen shows the credit logo', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'dufs_url': 'https://old.host',
      'dufs_user': 'bookguard',
      'dufs_password': 'old',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: SettingsScreen(store: LoginStore(), onSaved: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(KuhyCredit), findsOneWidget);
  });

  // The desktop build has no settings page, so its home bar carries the
  // credit; the phone keeps it on the settings page only.
  for (final withSettings in [false, true]) {
    testWidgets('home bar credit when settings page: $withSettings', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: HomeScreen(
            api: FakeApi(state: sampleState()),
            desktop: !withSettings,
            settingsPage: withSettings ? () => const SizedBox() : null,
            refreshEvery: const Duration(seconds: 1),
          ),
        ),
      );
      await settle(tester);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(KuhyCredit),
        ),
        withSettings ? findsNothing : findsOneWidget,
      );
    });
  }
}
