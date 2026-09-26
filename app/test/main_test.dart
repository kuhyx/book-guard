import 'package:book_guard_app/main.dart' as entry;
import 'package:book_guard_app/src/app.dart';
import 'package:book_guard_app/src/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('main runs the phone app, which asks for a login first', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    entry.main();
    await settle(tester);
    // Tests run on the VM, so this is the phone build (kIsWeb is false).
    expect(
      tester.widget<BookGuardApp>(find.byType(BookGuardApp)).desktop,
      isFalse,
    );
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
