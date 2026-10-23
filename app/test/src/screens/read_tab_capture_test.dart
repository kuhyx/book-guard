import 'dart:convert';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/fake_api.dart';
import '../../support/fake_reader.dart';
import '../../support/states.dart';

final _bytes = Uint8List.fromList([0xff, 0xd8, 0xff]);

/// What the photo pipeline logged, as `event` names in order.
Future<List<String>> _events(GuardApi api) async => [
  for (final name in await api.store.list('eventbox/'))
    if (name.endsWith('.body'))
      (jsonDecode(utf8.decode((await api.store.read(name))!))
              as Map<String, dynamic>)['event']
          as String,
];

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  final reader = FakeReader(
    fakeScan([(252, (left: 17, top: 54, right: 23, bottom: 58))]),
  );

  Future<void> pump(
    WidgetTester tester, {
    List<Capture> captures = const [],
    XFile? photo,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTab(
      tester,
      ReadTab(
        api: api,
        state: readingState(),
        desktop: false,
        onChanged: () async {},
        reader: reader,
        captures: captures,
        photoSource: ({required camera}) async => photo,
      ),
    );
  }

  testWidgets('leaving the review keeps the photo to finish later', (
    tester,
  ) async {
    // 2026-10-23 10:06: "Page 252?" was on screen, the app was left, and
    // the photo -- only ever in memory -- was gone.
    await pump(tester, photo: XFile.fromData(_bytes, path: '/DCIM/IMG.jpg'));
    await tapVisible(tester, find.text('Start reading'));
    await settle(tester, 10);
    expect(find.text('Page 252?'), findsOneWidget);
    await tester.pageBack();
    await settle(tester, 10);
    await tester.pump(const Duration(seconds: 1)); // the route animates out
    expect(api.photos, isEmpty);
    expect(find.textContaining('Photo kept on the phone'), findsOneWidget);
    final [kept] = await api.captures.pending();
    expect((kept.label, kept.fileName), ('start', 'IMG.jpg'));
    expect(await _events(api), [
      'camera',
      'captured',
      'scanned',
      'review-left',
    ]);

    await pump(tester, captures: [kept]);
    final finish = find.textContaining('Finish the start photo from');
    expect(finish, findsOneWidget);
    await tapVisible(tester, finish);
    await settle(tester, 10);
    await tester.tap(find.text('Send p. 252'));
    await settle(tester, 10);
    expect(api.photos, {'start_IMG.jpg': _bytes});
    expect(api.notes['start_IMG.jpg']?.page, 252);
    expect(await api.captures.pending(), isEmpty);
    expect((await _events(api)).skip(4), [
      'resumed',
      'scanned',
      'reviewed',
      'queued',
      'sent',
      'pc-not-yet',
    ]);
  });

  testWidgets('retake deliberately discards the stored photo', (tester) async {
    await pump(tester, photo: XFile.fromData(_bytes, path: '/DCIM/IMG.jpg'));
    await tapVisible(tester, find.text('Start reading'));
    await settle(tester, 10);
    await tester.tap(find.text('Retake'));
    await settle(tester, 10);
    expect(await api.captures.pending(), isEmpty);
    expect(await _events(api), ['camera', 'captured', 'scanned', 'discarded']);
  });

  testWidgets('a camera that returns nothing is logged', (tester) async {
    await pump(tester);
    await tapVisible(tester, find.text('Start reading'));
    await settle(tester, 10);
    expect(await api.captures.launched(), isNull);
    expect(await _events(api), ['camera', 'no-photo']);
  });

  testWidgets('a photo already sent is not sent twice', (tester) async {
    final gone = Capture(
      id: 'a1',
      label: 'start',
      fileName: 'IMG.jpg',
      takenAt: DateTime(2026, 10, 23, 10, 6),
    );
    await pump(tester, captures: [gone]);
    expect(find.text('Finish the start photo from 10:06'), findsOneWidget);
    await tapVisible(tester, find.text('Finish the start photo from 10:06'));
    await settle(tester, 10);
    expect(find.byType(PhotoReview), findsNothing);
    expect(api.photos, isEmpty);
  });
}
