import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
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
    expect(find.text('James Clear - p. 320 - ebook attached'), findsOneWidget);
  });

  testWidgets('describes what a bare book is still missing', (tester) async {
    await pump(
      tester,
      state: sampleState({
        'book': {'title': 'Bare'},
      }),
    );
    expect(
      find.text('Unknown author - last page not set - no ebook file'),
      findsOneWidget,
    );
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
    expect(
      find.text(
        'Unknown author - last page not set - no ebook file\n'
        'Chapter 1 of 1: Wstęp',
      ),
      findsOneWidget,
    );
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
    expect(find.textContaining('\n2 chapters'), findsOneWidget);
  });

  testWidgets('Edit opens the form; saving refreshes', (tester) async {
    await pump(tester);
    await tapVisible(tester, find.byTooltip('Edit book'));
    await tester.pumpAndSettle();
    expect(find.text('Edit book'), findsOneWidget);
    await tapVisible(tester, find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.sent.single.type, 'edit_book');
    expect(find.text('Fill from ISBN'), findsNothing);
    expect(changed, 1);
  });

  testWidgets('leaving the form without saving does not refresh', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, find.byTooltip('Edit book'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(changed, 0);
  });

  testWidgets('defaults to the file_selector ebook picker', (tester) async {
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
    await tapVisible(tester, find.byIcon(Icons.attach_file));
    await settle(tester);
    expect(calls.single.method, 'openFile');
    expect('${calls.single.arguments}', contains('epub'));
    expect(api.books, isEmpty);
  });
}
