import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:book_guard_app/src/screens/edit_book_screen.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_book.dart';
import '../../support/states.dart';

void main() {
  late FakeApi api;
  late int changed;
  late List<bool> cameras;

  setUp(() {
    api = FakeApi();
    changed = 0;
    cameras = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    GuardState? state,
    XFile? file,
    XFile? photo,
    bool desktop = false,
  }) => pumpTab(
    tester,
    BookTab(
      api: api,
      state: state ?? sampleState(),
      onChanged: () async => changed++,
      bookSource: () async => file,
      desktop: desktop,
      photoSource: ({required camera}) async {
        cameras.add(camera);
        return photo;
      },
    ),
  );

  testWidgets('describes a fully registered book', (tester) async {
    await pump(tester);
    expect(find.text('Atomic Habits'), findsOneWidget);
    expect(find.text('James Clear'), findsOneWidget);
    expect(find.text('320'), findsOneWidget);
    expect(iconLabeled('Ebook attached'), findsOneWidget);
    expect(iconLabeled('Last page not set'), findsNothing);
  });

  testWidgets('describes what a bare book is still missing', (tester) async {
    await pump(
      tester,
      state: sampleState({
        'book': {'title': 'Bare'},
      }),
    );
    expect(iconLabeled('Last page not set'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
    expect(iconLabeled('No ebook file'), findsOneWidget);
    expect(iconLabeled('Ebook attached'), findsNothing);
  });

  testWidgets('no book is an outline illustration, no sentence', (
    tester,
  ) async {
    await pump(tester, state: sampleState({'book': null}));
    expect(iconLabeled('No book yet'), findsOneWidget);
    expect(iconLabeled('Edit book'), findsNothing);
    expect(iconLabeled('Attach book file'), findsNothing);
  });

  testWidgets('a known chapter or chapter count shows on the card', (
    tester,
  ) async {
    await pump(
      tester,
      state: sampleState({
        'book': {
          'title': 'Cesarz',
          'chapters': [
            {'start': 9, 'title': 'Wstęp'},
          ],
          'chapter': {'number': 1, 'of': 1, 'title': 'Wstęp'},
        },
      }),
    );
    expect(find.text('1/1'), findsOneWidget);
    expect(find.text('Wstęp'), findsOneWidget);
    await pump(
      tester,
      state: sampleState({
        'book': {
          'title': 'Cesarz',
          'chapters': [
            {'start': 9, 'title': 'Wstęp'},
            {'start': 25, 'title': 'Jeden'},
          ],
        },
      }),
    );
    expect(iconLabeled('Chapters'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('Edit opens the form; saving refreshes', (tester) async {
    await pump(tester);
    await tapLabeled(tester, 'Edit book');
    await tester.pumpAndSettle();
    expect(find.byType(EditBookScreen), findsOneWidget);
    await tapLabeled(tester, 'Save');
    await tester.pumpAndSettle();
    expect(api.sent.single.type, 'edit_book');
    expect(find.byType(EditBookScreen), findsNothing);
    expect(changed, 1);
  });

  testWidgets('leaving the form without saving does not refresh', (
    tester,
  ) async {
    await pump(tester);
    await tapLabeled(tester, 'Edit book');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(changed, 0);
  });

  testWidgets('defaults to the file_selector book picker', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await pumpTab(
      tester,
      BookTab(api: api, state: sampleState(), onChanged: () async {}),
    );
    await tapLabeled(tester, 'Attach book file');
    await settle(tester);
    await tester.tap(iconLabeled('Choose file'));
    await settle(tester);
    expect(calls.single.method, 'openFile');
    // flutter_test runs as Android: no filter, the extension is checked later.
    expect('${calls.single.arguments}', contains('acceptedTypeGroups: []'));
    expect(api.books, isEmpty);
  });
}
