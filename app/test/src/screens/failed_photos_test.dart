import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/fake_reader.dart';

JournalEntry _entry(String name, String label, int? page) => JournalEntry(
  name: name,
  label: label,
  sha: 'f' * 64,
  takenAt: DateTime.utc(2026, 10, 3, 12, 27),
  page: page,
);

GuardState _state(List<PhotoInfo> photos) =>
    GuardState.fromJson(const {}).copyWithPhotos(photos);

extension on GuardState {
  GuardState copyWithPhotos(List<PhotoInfo> photos) => GuardState(
    locked: locked,
    reason: reason,
    book: book,
    pace: pace,
    todo: todo,
    sessions: sessions,
    openStart: openStart,
    generatedAt: generatedAt,
    photos: photos,
  );
}

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> pump(
    WidgetTester tester, {
    required GuardState? state,
    required List<JournalEntry> journal,
    FakeReader? reader,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTab(
      tester,
      SingleChildScrollView(
        child: FailedPhotos(
          api: api,
          state: state,
          journal: journal,
          reader: reader,
          onChanged: () async {},
        ),
      ),
    );
    await settle(tester, 10);
  }

  test('what counts as failed', () {
    final pcRejected = reading(
      name: 'start_a.jpg',
      kind: 'other',
      page: null,
      status: 'rejected',
      reason: 'no page number found',
    );
    final journal = [
      _entry('start_a.jpg', 'start', 51), // PC rejected it
      _entry('stop_b.jpg', 'stop', null), // phone found nothing, PC not yet
      _entry('check19_c.jpg', 'check19', 19), // fine
      _entry('stop_d.jpg', 'stop', null), // phone found nothing, PC read it
    ];
    final failed = failedPhotos(
      _state([pcRejected, reading(name: 'stop_d.jpg', page: 80)]),
      journal,
    );
    expect(failed.map((f) => f.entry.name), ['stop_b.jpg', 'start_a.jpg']);
    expect(failed.first.reason, 'the phone found no page number');
    expect(failed.last.pc, pcRejected);
    expect(failedPhotos(null, const []), isEmpty);
  });

  testWidgets('nothing failed: nothing shown', (tester) async {
    await pump(tester, state: null, journal: const []);
    expect(find.text('Failed photos'), findsNothing);
  });

  testWidgets('box the number: the PC is asked to read that box', (
    tester,
  ) async {
    await api.store.write('photos/check19_a.jpg', Uint8List.fromList([1, 2]));
    final pc = reading(
      name: 'check19_a.jpg',
      kind: 'other',
      page: null,
      status: 'rejected',
      reason: 'page 19 not found on the photo',
    );
    api.onSend = (r) async =>
        const GuardResponse(ok: true, message: 'Read as p. 19.');
    final reader = FakeReader(fakeScan([]), boxed: 19);
    await pump(
      tester,
      state: _state([pc]),
      journal: [_entry('check19_a.jpg', 'check19', null)],
      reader: reader,
    );
    expect(find.textContaining('rejected: page 19 not found'), findsOneWidget);
    await tester.tap(find.text('Box the number'));
    await settle(tester, 10);
    final photo = tester.getTopLeft(find.byType(Image).last);
    final k = tester.getSize(find.byType(Image).last).width / 40;
    await tester.dragFrom(
      photo + const Offset(15, 50) * k,
      const Offset(10, 6) * k,
    );
    await settle(tester, 10);
    await tester.tap(find.text('Send p. 19'));
    await settle(tester, 10);
    final sent = api.sent.single;
    expect(sent.type, 'box');
    expect(sent.body['photo'], 'check19_a.jpg');
    expect(sent.body['box'], isA<List<int>>());
    // The number the phone read in the box is sent: the PC takes it as is.
    expect(sent.body['page'], 19);
    expect(find.text('Read as p. 19.'), findsOneWidget);
  });

  testWidgets('a refused box shows why', (tester) async {
    await api.store.write('photos/start_a.jpg', Uint8List.fromList([1]));
    api.onSend = (r) async =>
        const GuardResponse(ok: false, message: 'Still no page number');
    final reader = FakeReader(
      fakeScan([(7, (left: 1, top: 50, right: 5, bottom: 55))]),
    );
    await pump(
      tester,
      state: _state([
        reading(name: 'start_a.jpg', kind: 'other', status: 'rejected'),
      ]),
      journal: [_entry('start_a.jpg', 'start', 7)],
      reader: reader,
    );
    await tester.tap(find.text('Box the number'));
    await settle(tester, 10);
    await tester.tap(find.text('Send p. 7'));
    await settle(tester, 10);
    expect(find.text('Still no page number'), findsOneWidget);
  });

  testWidgets('cancelling the review sends nothing', (tester) async {
    await api.store.write('photos/start_a.jpg', Uint8List.fromList([1]));
    await pump(
      tester,
      state: _state([
        reading(name: 'start_a.jpg', kind: 'other', status: 'rejected'),
      ]),
      journal: [_entry('start_a.jpg', 'start', null)],
      reader: FakeReader(fakeScan([])),
    );
    await tester.tap(find.text('Box the number'));
    await settle(tester, 10);
    await tester.tap(find.text('Retake'));
    await settle(tester, 10);
    expect(api.sent, isEmpty);
  });

  testWidgets('"this should not fail" files a report once', (tester) async {
    await api.store.write('photos/stop_b.jpg', Uint8List.fromList([1, 2, 3]));
    await pump(
      tester,
      state: _state(const []),
      journal: [_entry('stop_b.jpg', 'stop', null)],
    );
    expect(find.text('Box the number'), findsNothing); // no PC reading yet
    await tester.tap(find.text('This should not fail'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await api.reported('stop_b.jpg'), isFalse);
    await tester.tap(find.text('This should not fail'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '103');
    await tester.enterText(
      find.byType(TextField).last,
      'clear 103 at the bottom',
    );
    await tester.tap(find.text('Send report'));
    await settle(tester, 10);
    expect(await api.reported('stop_b.jpg'), isTrue);
    expect(find.text('Reported'), findsOneWidget);
    final notes = await api.store.list('outbox/');
    expect(notes.where((n) => n.endsWith('.path')), hasLength(2));
  });

  testWidgets('a photo no longer on the phone cannot be reported', (
    tester,
  ) async {
    await pump(
      tester,
      state: _state(const []),
      journal: [_entry('stop_gone.jpg', 'stop', null)],
    );
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'This should not fail'),
    );
    expect(button.onPressed, isNull);
    expect(find.byIcon(Icons.image_not_supported), findsOneWidget);
  });
}
