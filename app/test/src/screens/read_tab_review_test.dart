import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/fake_reader.dart';
import '../../support/finders_read.dart';
import '../../support/states.dart';

final _bytes = Uint8List.fromList([0xff, 0xd8, 0xff]);

// A pencilled number the reader suggests is kept with the photo, never sent
// as its page.

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> pump(
    WidgetTester tester,
    FakeReader reader, {
    GuardState? state,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTab(
      tester,
      ReadTab(
        api: api,
        state: state,
        desktop: false,
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

  testWidgets('the number the phone read is shown boxed and sent with it', (
    tester,
  ) async {
    final reader = FakeReader(
      fakeScan([
        (3, (left: 18, top: 4, right: 22, bottom: 8)),
        (51, (left: 17, top: 54, right: 23, bottom: 58)),
      ]),
    );
    api.readings['stop_IMG.jpg'] = reading(name: 'stop_IMG.jpg', page: 51);
    await pump(tester, reader, state: readingState(openStart: 31));
    await open(tester, spoken('Stop reading'));
    expect(find.byType(PhotoReview), findsOneWidget);
    // The chapter numeral 3 is before the start, so 51 is the only option.
    expect(chosenPage(51), findsOneWidget);
    expect(pulse(), findsNothing);
    await tester.tap(spoken('Retake'));
    await settle(tester, 10);
    // A start with no history: 3 or 51 is unclear until one is tapped.
    api.state = null;
    await pump(tester, reader, state: readingState());
    await open(tester, spoken('Start reading'));
    expect(pulse(), findsOneWidget);
    expect(rejected(RejectGlyph.unclear), findsOneWidget);
    // Tapping the boxed 51 chooses it.
    final photo = tester.getTopLeft(find.byType(Image));
    await tester.tapAt(photo + const Offset(20, 56) * _scale(tester));
    await settle(tester);
    expect(chosenPage(51), findsOneWidget);
    expect(pulse(), findsNothing);
    await tester.tap(spoken('Send the page number'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg']?.page, 51);
    expect(api.notes['start_IMG.jpg']?.box, (
      left: 170,
      top: 540,
      right: 230,
      bottom: 580,
    ));
  });

  testWidgets('a start takes the number nearest the last session end', (
    tester,
  ) async {
    final reader = FakeReader(
      fakeScan([
        (3, (left: 18, top: 4, right: 22, bottom: 8)),
        (51, (left: 17, top: 54, right: 23, bottom: 58)),
      ]),
    );
    await pump(tester, reader, state: readingState(lastEnd: 51));
    await open(tester, spoken('Start reading'));
    expect(chosenPage(51), findsOneWidget);
    expect(pulse(), findsNothing);
    await tester.tap(spoken('Send the page number'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg']?.page, 51);
  });

  testWidgets('nothing found: draw a box, the phone reads it', (tester) async {
    final reader = FakeReader(fakeScan([]), boxed: 7);
    await pump(tester, reader, state: readingState());
    await open(tester, spoken('Start reading'));
    expect(pulse(), findsOneWidget);
    expect(rejected(RejectGlyph.noNumber), findsOneWidget);
    final photo = tester.getTopLeft(find.byType(Image));
    final k = _scale(tester);
    await tester.dragFrom(
      photo + const Offset(15, 50) * k,
      const Offset(10, 6) * k,
    );
    await settle(tester, 10);
    expect(reader.asked, hasLength(1));
    expect(chosenPage(7), findsOneWidget);
    await tester.tap(spoken('Send the page number'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg']?.page, 7);
  });

  testWidgets('an illegible box asks for a tighter one; send anyway works', (
    tester,
  ) async {
    final reader = FakeReader(fakeScan([]));
    await pump(tester, reader, state: readingState());
    await open(tester, spoken('Start reading'));
    final photo = tester.getTopLeft(find.byType(Image));
    final k = _scale(tester);
    await tester.dragFrom(
      photo + const Offset(15, 50) * k,
      const Offset(10, 6) * k,
    );
    await settle(tester, 10);
    // Still no number: the pulse stays and the glyph is the no-number one.
    expect(pulse(), findsOneWidget);
    expect(anyRejection(), findsOneWidget);
    expect(rejected(RejectGlyph.noNumber), findsOneWidget);
    await tester.tap(spoken('Send anyway'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg'], (page: null, box: null));
  });

  testWidgets('retake discards the photo', (tester) async {
    final reader = FakeReader(fakeScan([]));
    await pump(tester, reader, state: readingState());
    await open(tester, spoken('Start reading'));
    await tester.tap(spoken('Retake'));
    await settle(tester, 10);
    expect(cueWith(Icons.delete_outline), findsOneWidget);
    expect(api.photos, isEmpty);
  });

  testWidgets('offline, the photo is kept on the phone', (tester) async {
    api.offline = true;
    final reader = FakeReader(
      fakeScan([(19, (left: 17, top: 54, right: 23, bottom: 58))]),
    );
    await pump(tester, reader, state: readingState(check: 19));
    await open(tester, find.byIcon(Icons.fact_check));
    expect(chosenPage(19), findsOneWidget);
    await tester.tap(spoken('Send the page number'));
    await settle(tester, 10);
    expect(cueWith(Icons.outbox), findsOneWidget);
    expect(
      find.descendant(of: cueWith(Icons.outbox), matching: find.text('19')),
      findsOneWidget,
    );
  });

  testWidgets('an unreadable image goes up without a number, logged', (
    tester,
  ) async {
    await pump(tester, FakeReader(null), state: readingState());
    await open(tester, spoken('Start reading'));
    expect(api.notes['start_IMG.jpg'], (page: null, box: null));
    expect(await api.errors.diagnostics(), contains('unreadable image'));
  });

  testWidgets('a pencilled number is kept with the photo, not sent as page', (
    tester,
  ) async {
    final reader = FakeReader(fakeScan([]).withPencil(29));
    await pump(tester, reader, state: readingState());
    await open(tester, spoken('Start reading'));
    await tester.tap(spoken('Send anyway'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg']?.page, isNull);
    expect(api.pencils['start_IMG.jpg'], 29);
  });

  testWidgets('a number the reader chose carries no pencil suggestion', (
    tester,
  ) async {
    final reader = FakeReader(
      fakeScan([(51, (left: 17, top: 54, right: 23, bottom: 58))])
          .withPencil(29),
    );
    await pump(tester, reader, state: readingState(openStart: 31));
    await open(tester, spoken('Stop reading'));
    await tester.tap(spoken('Send the page number'));
    await settle(tester, 10);
    expect(api.notes['stop_IMG.jpg']?.page, 51);
    expect(api.pencils['stop_IMG.jpg'], isNull);
  });
}

/// Preview pixels -> logical pixels, as the review screen laid them out.
double _scale(WidgetTester tester) =>
    tester.getSize(find.byType(Image)).width / 40;
