import 'package:book_guard_app/src/login_store.dart';
import 'package:book_guard_app/src/screens/settings_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  late int saved;

  setUp(() {
    saved = 0;
    FlutterSecureStorage.setMockInitialValues({
      'dufs_url': 'https://old.host',
      'dufs_user': 'bookguard',
      'dufs_password': 'old',
    });
  });

  Widget screen() =>
      SettingsScreen(store: LoginStore(), onSaved: () async => saved++);

  testWidgets('fills the fields from the keystore', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildLightTheme(), home: screen()),
    );
    await settle(tester);
    expect(find.text('https://old.host'), findsOneWidget);
    expect(find.text('bookguard'), findsOneWidget);
    final password = tester.widget<TextField>(_field('Password'));
    expect(password.obscureText, isTrue);
    expect(password.controller?.text, 'old');
  });

  testWidgets('refuses to save an incomplete login', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildLightTheme(), home: screen()),
    );
    await settle(tester);
    await tester.enterText(_field('Password'), '   ');
    await tapVisible(tester, find.text('Save'));
    await settle(tester);
    expect(find.text('Fill in all three fields.'), findsOneWidget);
    expect(saved, 0);
    expect(
      await const FlutterSecureStorage().read(key: 'dufs_password'),
      'old',
    );
  });

  testWidgets('saves a trimmed login and pops back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => screen())),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('dufs URL'), ' https://new.host// ');
    await tester.enterText(_field('User'), ' me ');
    await tester.enterText(_field('Password'), ' pw ');
    await tapVisible(tester, find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(find.text('Connection'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    final login = await LoginStore().load();
    expect(
      [login.url, login.user, login.password],
      ['https://new.host', 'me', 'pw'],
    );
  });

  testWidgets('as the root page it saves without popping', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildLightTheme(), home: screen()),
    );
    await settle(tester);
    await tapVisible(tester, find.text('Save'));
    await settle(tester);
    expect(saved, 1);
    expect(find.text('Connection'), findsOneWidget);
  });

  testWidgets('closing before the keystore answers is harmless', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildLightTheme(), home: screen()),
    );
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(find.byType(SettingsScreen), findsNothing);
  });
}
