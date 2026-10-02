import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/states.dart';

final _epub = Uint8List.fromList([0x50, 0x4b]);

void main() {
  late FakeApi api;
  late int changed;

  setUp(() {
    api = FakeApi();
    changed = 0;
  });

  Future<void> pump(WidgetTester tester, {GuardState? state, XFile? file}) =>
      pumpTab(
        tester,
        BookTab(
          api: api,
          state: state ?? sampleState(),
          onChanged: () async => changed++,
          bookSource: () async => file,
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

  testWidgets('Set sends the last page as a number', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, ' 311 ');
    await tapVisible(tester, find.text('Set'));
    await settle(tester);
    expect(api.sent.single.type, 'set_pages');
    expect(api.sent.single.body, {'pages': 311});
    expect(find.text('done set_pages'), findsOneWidget);
    expect(changed, 1);
  });

  testWidgets('Set with no number sends null for the PC to refuse', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, find.text('Set'));
    await settle(tester);
    expect(api.sent.single.body, {'pages': null});
  });

  testWidgets('a refused Set is shown as an error', (tester) async {
    api.onSend = (_) async =>
        const GuardResponse(ok: false, message: 'Must be positive');
    await pump(tester);
    await tapVisible(tester, find.text('Set'));
    await settle(tester);
    expect(find.text('Must be positive'), findsOneWidget);
  });

  testWidgets('attaching uploads the picked file', (tester) async {
    await pump(tester, file: XFile.fromData(_epub, path: '/b/Atomic.epub'));
    await tapVisible(tester, find.byIcon(Icons.attach_file));
    await settle(tester);
    expect(api.books, {'Atomic.epub': _epub});
    expect(
      find.text('Uploaded - the PC indexes it in a few minutes.'),
      findsOneWidget,
    );
    expect(changed, 1);
  });

  testWidgets('a cancelled pick uploads nothing', (tester) async {
    await pump(tester);
    await tapVisible(tester, find.byIcon(Icons.attach_file));
    await settle(tester);
    expect(api.books, isEmpty);
    expect(find.textContaining('Uploaded'), findsNothing);
  });

  testWidgets('an upload failure is shown', (tester) async {
    api.uploadError = shareDown();
    await pump(tester, file: XFile.fromData(_epub, path: '/b/a.pdf'));
    await tapVisible(tester, find.byIcon(Icons.attach_file));
    await settle(tester);
    expect(find.text('dufs Reading/x failed (500)'), findsOneWidget);
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
