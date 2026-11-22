import 'dart:async';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/screens/scanning_review.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/fake_reader.dart';
import '../../support/finders_read.dart';
import '../../support/keypad.dart';
import '../../support/states.dart';

final _bytes = Uint8List.fromList([0xff, 0xd8, 0xff]);

/// A reader whose scan lands only when the test says so.
class _SlowReader extends FakeReader {
  new() : super(null);

  final _done = Completer<PageScan?>();

  void land(PageScan scan) => _done.complete(scan);

  @override
  Future<PageScan?> scan(
    Uint8List bytes, {
    PageContext context = const PageContext(),
  }) => _done.future;
}

void main() {
  testWidgets('a scan that lands after the tab has gone opens the review', (
    tester,
  ) async {
    // 2026-11-22 11:31-11:35: four scans of 15 s each, the Read tab gone
    // before each landed, "review-left" and back to the same button.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeApi();
    final reader = _SlowReader();
    final show = ValueNotifier(true);
    final tab = ReadTab(
      api: api,
      state: readingState(),
      desktop: false,
      onChanged: () async {},
      reader: reader,
      photoSource: ({required camera}) async =>
          XFile.fromData(_bytes, path: '/DCIM/IMG.jpg'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: show,
            builder: (_, on, _) => on ? tab : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tapVisible(tester, spoken('Start reading'));
    await settle(tester, 10);
    show.value = false; // another tab, a rebuild: the Read tab is gone
    await settle(tester, 10);
    reader.land(fakeScan([(252, (left: 17, top: 54, right: 23, bottom: 58))]));
    await settle(tester, 20);
    expect(find.byType(PhotoReview), findsOneWidget);
    await tester.tap(spoken('Send the page number'));
    await settle(tester, 20);
    expect(api.notes['start_IMG.jpg']?.page, 252);
  });

  testWidgets('the review opens before the scan lands, the keypad works', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeApi();
    await pumpTab(
      tester,
      ReadTab(
        api: api,
        state: readingState(),
        desktop: false,
        onChanged: () async {},
        reader: _SlowReader(), // never lands
        photoSource: ({required camera}) async =>
            XFile.fromData(_bytes, path: '/DCIM/IMG.jpg'),
      ),
    );
    await tapVisible(tester, spoken('Start reading'));
    await settle(tester, 10);
    expect(find.byType(ScanningReview), findsOneWidget);
    await typeOnKeypad(tester, 260);
    await settle(tester, 20);
    expect(api.notes['start_IMG.jpg']?.page, 260);
  });
}
