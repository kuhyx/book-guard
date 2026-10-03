import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/fake_api.dart';
import '../../support/fake_reader.dart';
import '../../support/states.dart';

final _bytes = Uint8List.fromList([0xff, 0xd8, 0xff]);

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

  Future<void> open(WidgetTester tester, String button) async {
    await tapVisible(tester, find.text(button));
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
    await open(tester, 'Stop reading');
    expect(find.byType(PhotoReview), findsOneWidget);
    // The chapter numeral 3 is before the start, so 51 is the only option.
    expect(find.text('Page 51?'), findsOneWidget);
    await tester.tap(find.text('Retake'));
    await settle(tester, 10);
    // A start with no history: 3 or 51 is unclear until one is tapped.
    api.state = null;
    await pump(tester, reader, state: readingState());
    await open(tester, 'Start reading');
    expect(find.text('Box the page number'), findsOneWidget);
    expect(find.textContaining('unclear (3 or 51)'), findsOneWidget);
    // Tapping the boxed 51 chooses it.
    final photo = tester.getTopLeft(find.byType(Image));
    await tester.tapAt(photo + const Offset(20, 56) * _scale(tester));
    await settle(tester);
    expect(find.text('Page 51?'), findsOneWidget);
    await tester.tap(find.text('Send p. 51'));
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
    await open(tester, 'Start reading');
    expect(find.text('Page 51?'), findsOneWidget);
    await tester.tap(find.text('Send p. 51'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg']?.page, 51);
  });

  testWidgets('nothing found: draw a box, the phone reads it', (tester) async {
    final reader = FakeReader(fakeScan([]), boxed: 7);
    await pump(tester, reader, state: readingState());
    await open(tester, 'Start reading');
    expect(find.textContaining('No page number found.'), findsOneWidget);
    final photo = tester.getTopLeft(find.byType(Image));
    final k = _scale(tester);
    await tester.dragFrom(
      photo + const Offset(15, 50) * k,
      const Offset(10, 6) * k,
    );
    await settle(tester, 10);
    expect(reader.asked, hasLength(1));
    expect(find.text('Page 7?'), findsOneWidget);
    await tester.tap(find.text('Send p. 7'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg']?.page, 7);
  });

  testWidgets('an illegible box asks for a tighter one; send anyway works', (
    tester,
  ) async {
    final reader = FakeReader(fakeScan([]));
    await pump(tester, reader, state: readingState());
    await open(tester, 'Start reading');
    final photo = tester.getTopLeft(find.byType(Image));
    final k = _scale(tester);
    await tester.dragFrom(
      photo + const Offset(15, 50) * k,
      const Offset(10, 6) * k,
    );
    await settle(tester, 10);
    expect(find.textContaining('draw it tighter'), findsOneWidget);
    await tester.tap(find.text('Send anyway'));
    await settle(tester, 10);
    expect(api.notes['start_IMG.jpg'], (page: null, box: null));
  });

  testWidgets('retake discards the photo', (tester) async {
    final reader = FakeReader(fakeScan([]));
    await pump(tester, reader, state: readingState());
    await open(tester, 'Start reading');
    await tester.tap(find.text('Retake'));
    await settle(tester, 10);
    expect(find.text('Photo discarded - take it again.'), findsOneWidget);
    expect(api.photos, isEmpty);
  });

  testWidgets('offline, the photo is kept on the phone', (tester) async {
    api.offline = true;
    final reader = FakeReader(
      fakeScan([(19, (left: 17, top: 54, right: 23, bottom: 58))]),
    );
    await pump(tester, reader, state: readingState(check: 19));
    await open(tester, 'Photograph page 19');
    expect(find.text('Page 19?'), findsOneWidget);
    await tester.tap(find.text('Send p. 19'));
    await settle(tester, 10);
    expect(find.textContaining('Saved on the phone (p. 19)'), findsOneWidget);
  });

  testWidgets('an unreadable image goes up without a number, logged', (
    tester,
  ) async {
    await pump(tester, FakeReader(null), state: readingState());
    await open(tester, 'Start reading');
    expect(api.notes['start_IMG.jpg'], (page: null, box: null));
    expect(await api.errors.diagnostics(), contains('unreadable image'));
  });
}

/// Preview pixels -> logical pixels, as the review screen laid them out.
double _scale(WidgetTester tester) =>
    tester.getSize(find.byType(Image)).width / 40;
