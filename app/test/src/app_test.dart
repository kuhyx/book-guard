import 'package:book_guard_app/src/app.dart';
import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:book_guard_app/src/login_store.dart';
import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:book_guard_app/src/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/finders_a.dart';
import '../support/states.dart';

void main() {
  late List<DavClient> davs;

  setUp(() => davs = []);

  GuardApi factory(DavClient dav) {
    davs.add(dav);
    return FakeApi(state: sampleState());
  }

  Future<void> pump(WidgetTester tester, {required bool desktop}) async {
    await tester.pumpWidget(
      BookGuardApp(
        desktop: desktop,
        loginStore: LoginStore(),
        apiFactory: factory,
      ),
    );
    // HomeScreen refreshes on a timer; dispose it when the test ends.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('desktop talks to the wrapper at /dav without a login', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await pump(tester, desktop: true);
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(iconLabeled('connection'), findsNothing);
    final dav = davs.single;
    expect(dav.baseUrl, Uri.base.resolve('/dav').toString());
    expect(dav.user, isEmpty);
    expect(dav.password, isEmpty);
  });

  testWidgets('a phone without a password starts at Settings', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await pump(tester, desktop: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(davs, isEmpty);

    // The settings fields: url, user, password.
    await tester.enterText(fieldAt(2), 'secret');
    await tapVisible(tester, mainButton);
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    final dav = davs.single;
    expect(dav.baseUrl, kDefaultDufsUrl);
    expect(dav.user, kDefaultDufsUser);
    expect(dav.password, 'secret');
  });

  testWidgets('a saved phone login opens Home; Connection re-saves it', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'dufs_url': 'https://h',
      'dufs_user': 'u',
      'dufs_password': 'p',
    });
    await pump(tester, desktop: false);
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(davs.single.baseUrl, 'https://h');

    await tester.tap(iconLabeled('connection'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.enterText(fieldAt(1), 'v');
    await tapVisible(tester, mainButton);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(davs.map((d) => d.user), ['u', 'v']);
  });

  testWidgets('without a factory the real GuardApi is used', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'dufs_url': 'https://h',
      'dufs_user': 'u',
      'dufs_password': 'p',
    });
    await tester.pumpWidget(
      BookGuardApp(
        desktop: false,
        loginStore: LoginStore(),
        storeFactory: () async => MemoryStore(),
      ),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await settle(tester, 20);
    expect(find.byType(HomeScreen), findsOneWidget);
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    expect(home.api, isNot(isA<FakeApi>()));
    expect(home.api.dav.baseUrl, 'https://h');
  });

  testWidgets('closing while the login loads is harmless', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(
      BookGuardApp(desktop: false, loginStore: LoginStore()),
    );
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(find.byType(BookGuardApp), findsNothing);
  });
}
