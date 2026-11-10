import 'package:book_guard_app/src/login_store.dart';
import 'package:book_guard_app/src/screens/reading_settings.dart';
import 'package:book_guard_app/src/screens/settings_screen.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_book.dart';

Finder _field(String label) => inputLabeled(label);

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
    // A link, a person and a key caption the three fields.
    for (final icon in [Icons.link, Icons.person, Icons.key]) {
      expect(find.byIcon(icon), findsOneWidget);
    }
    final password = tester.widget<TextField>(_field('Password'));
    expect(password.obscureText, isTrue);
    expect(password.controller?.text, 'old');
  });

  testWidgets('refuses to save an incomplete login: red field, error cue', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildLightTheme(), home: screen()),
    );
    await settle(tester);
    await tester.enterText(_field('Password'), '   ');
    expect(fieldIsRed(tester, 'Password'), isFalse);
    await tapLabeled(tester, 'Save');
    await settle(tester);
    expect(cueOf(CueKind.error), findsOneWidget);
    expect(fieldIsRed(tester, 'Password'), isTrue);
    expect(fieldIsRed(tester, 'User'), isFalse);
    expect(fieldIsRed(tester, 'dufs URL'), isFalse);
    expect(saved, 0);
    expect(
      await const FlutterSecureStorage().read(key: 'dufs_password'),
      'old',
    );
    // Typing into the red field takes the red away.
    await tester.enterText(_field('Password'), 'x');
    await tester.pump();
    expect(fieldIsRed(tester, 'Password'), isFalse);
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
    await tapLabeled(tester, 'Save');
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(find.byType(SettingsScreen), findsNothing);
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
    await tapLabeled(tester, 'Save');
    await settle(tester);
    expect(saved, 1);
    expect(find.byType(SettingsScreen), findsOneWidget);
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

  testWidgets('connected, it leads on to the reading settings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: SettingsScreen(
          store: LoginStore(),
          onSaved: () async {},
          api: FakeApi(),
        ),
      ),
    );
    await settle(tester);
    await tapLabeled(tester, 'Reading');
    await tester.pumpAndSettle();
    expect(find.byType(ReadingSettingsScreen), findsOneWidget);
  });

  testWidgets('the first-run login has no reading settings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildLightTheme(), home: screen()),
    );
    await settle(tester);
    expect(iconLabeled('Reading'), findsNothing);
    expect(find.byIcon(Icons.text_fields), findsNothing);
  });
}
