import 'package:book_guard_app/src/library.dart';
import 'package:book_guard_app/src/login_store.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:book_guard_app/src/screens/library_tab.dart';
import 'package:book_guard_app/src/screens/settings_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_api.dart';
import '../support/fake_share.dart';
import '../support/library_api.dart';
import '../support/library_json.dart';
import '../support/no_words.dart';
import '../support/no_words_home.dart';

// The zero-text guard over the library, a book and the settings page.
void main() {
  testWidgets('the library and a book paint no words', (tester) async {
    tallSurface(tester);
    final share = FakeShare();
    putLibrary(share, libraryJson());
    final api = libraryApi(share);
    await pumpTab(tester, LibraryTab(api: api, state: null));
    await settle(tester);
    expectNoWords(tester, content: content);
    final book = LibraryBook.fromJson(
      (libraryJson()['books'] as List).first as Map<String, dynamic>,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: LibraryBookScreen(api: api, book: book),
      ),
    );
    await settle(tester);
    expectNoWords(tester, content: content);
  });

  testWidgets('an empty library paints no words', (tester) async {
    await pumpTab(
      tester,
      LibraryTab(api: libraryApi(FakeShare()), state: null),
    );
    await settle(tester);
    expectNoWords(tester, content: content);
  });

  testWidgets('settings paint no words', (tester) async {
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
    await settle(tester);
    expectNoWords(tester, content: content);
  });
}
