import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
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

// The review screen's keypad: the number sent is whatever its field holds, and
// the number OCR offered travels beside it as `ocr_page`.

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> pump(
    WidgetTester tester,
    FakeReader? reader, {
    GuardState? state,
    bool desktop = false,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTab(
      tester,
      ReadTab(
        api: api,
        state: state,
        desktop: desktop,
        onChanged: () async {},
        reader: reader,
        photoSource: ({required camera}) async =>
            XFile.fromData(_bytes, path: '/DCIM/IMG.jpg'),
      ),
    );
  }

  Future<void> open(WidgetTester tester, Finder button) async {
    await tapVisible(tester, button);
    await settle(tester, 10);
  }

  testWidgets('a pencilled number only pre-fills the keypad', (tester) async {
    final reader = FakeReader(fakeScan([]).withPencil(29));
    await pump(tester, reader, state: readingState());
    await open(tester, spoken('Start reading'));
    await tester.tap(spoken('Type the page number'));
    await settle(tester, 10);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '29',
    );
    await tester.tap(spoken('Send the typed page number'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg']?.page, 29);
    // The pencil's number is what a reader offered: kept, so no correction.
    expect(api.ocrs['start_IMG.jpg'], 29);
  });

  testWidgets('OCR read 2, the keypad corrects it: 29 is sent, ocr 2 kept', (
    tester,
  ) async {
    final reader = FakeReader(
      fakeScan([(2, (left: 17, top: 54, right: 23, bottom: 58))]),
    );
    await pump(tester, reader, state: readingState());
    await open(tester, spoken('Start reading'));
    expect(chosenPage(2), findsOneWidget);
    await tester.tap(spoken('Type the page number'));
    await settle(tester, 10);
    // Pre-filled with the OCR's hit.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '2',
    );
    await tester.enterText(find.byType(TextField), '29');
    await tester.tap(spoken('Send the typed page number'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg']?.page, 29);
    // 29 is not the number in the box, so the box is not sent with it.
    expect(api.notes['start_IMG.jpg']?.box, isNull);
    expect(api.ocrs['start_IMG.jpg'], 2);
    final log = await api.errors.diagnostics();
    expect(log, contains('ocr corrected'));
    expect(log, contains('"ocr":2'));
    expect(log, contains('"page":29'));
  });

  testWidgets('the tick sends the OCR number, nothing to correct', (
    tester,
  ) async {
    final reader = FakeReader(
      fakeScan([(51, (left: 17, top: 54, right: 23, bottom: 58))]),
    );
    await pump(tester, reader, state: readingState(openStart: 31));
    await open(tester, spoken('Stop reading'));
    await tester.tap(spoken('Send the page number'));
    await settle(tester, 10);
    expect(api.notes['stop_IMG.jpg']?.page, 51);
    expect(api.ocrs['stop_IMG.jpg'], 51);
    expect(await api.errors.diagnostics(), isNot(contains('ocr corrected')));
  });

  testWidgets('typing the OCR number again is no correction', (tester) async {
    final reader = FakeReader(
      fakeScan([(51, (left: 17, top: 54, right: 23, bottom: 58))]),
    );
    await pump(tester, reader, state: readingState(openStart: 31));
    await open(tester, spoken('Stop reading'));
    await typeOnKeypad(tester, 51);
    expect(api.notes['stop_IMG.jpg']?.page, 51);
    expect(api.notes['stop_IMG.jpg']?.box, isNotNull);
    expect(await api.errors.diagnostics(), isNot(contains('ocr corrected')));
  });

  testWidgets('a drawn box read as another number is a correction', (
    tester,
  ) async {
    final reader = FakeReader(
      fakeScan([(51, (left: 17, top: 54, right: 23, bottom: 58))]),
      boxed: 52,
    );
    await pump(tester, reader, state: readingState(openStart: 31));
    await open(tester, spoken('Stop reading'));
    final photo = tester.getTopLeft(find.byType(Image));
    final k = _scale(tester);
    await tester.dragFrom(
      photo + const Offset(15, 20) * k,
      const Offset(10, 6) * k,
    );
    await settle(tester, 10);
    await tester.tap(spoken('Send the page number'));
    await settle(tester, 10);
    expect(api.notes['stop_IMG.jpg']?.page, 52);
    expect(api.ocrs['stop_IMG.jpg'], 51);
    expect(await api.errors.diagnostics(), contains('ocr corrected'));
  });

  testWidgets('cancelling the keypad returns to the review screen', (
    tester,
  ) async {
    final reader = FakeReader(fakeScan([]));
    await pump(tester, reader, state: readingState());
    await open(tester, spoken('Start reading'));
    await tester.tap(spoken('Type the page number'));
    await settle(tester, 10);
    await tester.tap(spoken('Cancel'));
    await settle(tester, 40); // the dialog fades out
    expect(find.byType(PhotoReview), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(api.notes, isEmpty);
  });

  testWidgets('desktop: the keypad is filled before the photo is sent', (
    tester,
  ) async {
    await pump(tester, null, state: readingState(), desktop: true);
    await open(tester, spoken('Start reading'));
    expect(api.notes, isEmpty);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '40');
    await tester.tap(spoken('Send the typed page number'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg']?.page, 40);
    expect(api.ocrs['start_IMG.jpg'], isNull);
  });

  testWidgets('desktop: cancelling the keypad sends nothing', (tester) async {
    await pump(tester, null, state: readingState(), desktop: true);
    await open(tester, spoken('Start reading'));
    await tester.tap(spoken('Cancel'));
    await settle(tester, 10);
    expect(api.notes, isEmpty);
    expect(api.photos, isEmpty);
  });
}

/// Preview pixels -> logical pixels, as the review screen laid them out.
double _scale(WidgetTester tester) =>
    tester.getSize(find.byType(Image)).width / 40;
