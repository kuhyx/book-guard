import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_response.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_read.dart';

JournalEntry _entry(String name, String label, {int? page}) => JournalEntry(
  name: name,
  label: label,
  sha: 'f' * 64,
  takenAt: DateTime.utc(2026, 10, 3, 12, 27),
  page: page,
);

GuardState _state(List<PhotoInfo> photos) {
  final base = GuardState.fromJson(const {});
  return GuardState(
    locked: base.locked,
    reason: base.reason,
    book: base.book,
    pace: base.pace,
    todo: base.todo,
    sessions: base.sessions,
    openStart: base.openStart,
    generatedAt: base.generatedAt,
    photos: photos,
  );
}

final PhotoInfo _noNumber = reading(
  name: 'start_a.jpg',
  kind: 'other',
  page: null,
  status: 'rejected',
  reason: 'no page number found',
);

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  // No reader: this is the desktop web build, which has no on-device OCR.
  Future<void> pump(
    WidgetTester tester, {
    required List<PhotoInfo> photos,
    int? phonePage,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTab(
      tester,
      SingleChildScrollView(
        child: FailedPhotos(
          api: api,
          state: _state(photos),
          journal: [_entry('start_a.jpg', 'start', page: phonePage)],
          onChanged: () async {},
        ),
      ),
    );
    await settle(tester, 10);
  }

  testWidgets('a typed number is queued for the PC, which takes it as is', (
    tester,
  ) async {
    api.onSend = (r) async =>
        const GuardResponse(ok: true, code: 'read', data: {'page': 1});
    await pump(tester, photos: [_noNumber]);
    await tester.tap(spoken('Type the page number'));
    await settle(tester, 10);
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(spoken('Send the typed page number'));
    await settle(tester, 10);
    final sent = api.sent.single;
    expect(sent.type, 'type_page');
    expect(sent.body, {'photo': 'start_a.jpg', 'page': 1});
    expect(cueOf(CueKind.ok), findsOneWidget);
  });

  testWidgets('cancelling, or typing nothing, sends nothing', (tester) async {
    await pump(tester, photos: [_noNumber]);
    await tester.tap(spoken('Type the page number'));
    await settle(tester, 10);
    await tester.tap(spoken('Cancel'));
    await settle(tester, 10);
    await tester.tap(spoken('Type the page number'));
    await settle(tester, 10);
    await tester.tap(spoken('Send the typed page number'));
    await settle(tester, 10);
    expect(api.sent, isEmpty);
  });

  testWidgets('the keypad is numeric and keeps digits only', (tester) async {
    await pump(tester, photos: [_noNumber]);
    await tester.tap(spoken('Type the page number'));
    await settle(tester, 10);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType, TextInputType.number);
    await tester.enterText(find.byType(TextField), '1a2');
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('offered while the PC has not answered yet', (tester) async {
    // The photo still waits in the outbox (PC off): no verdict, no page.
    await pump(tester, photos: const []);
    expect(spoken('Type the page number'), findsOneWidget);
    expect(spoken('Box the number'), findsNothing);
    await tester.tap(spoken('Type the page number'));
    await settle(tester, 10);
    await tester.enterText(find.byType(TextField), '29');
    await tester.tap(spoken('Send the typed page number'));
    await settle(tester, 10);
    expect(api.sent.single.type, 'type_page');
    expect(api.sent.single.body, {'photo': 'start_a.jpg', 'page': 29});
  });

  testWidgets('not offered where a number was read', (tester) async {
    final read = reading(
      name: 'start_a.jpg',
      page: 51,
      status: 'rejected',
      reason: 'uploaded more than 7 days after it was taken',
    );
    await pump(tester, photos: [read]);
    expect(spoken('Type the page number'), findsNothing);
  });

  testWidgets('not offered where the phone read a number', (tester) async {
    final rejected = reading(
      name: 'start_a.jpg',
      page: null,
      status: 'rejected',
      reason: 'uploaded more than 7 days after it was taken',
    );
    await pump(tester, photos: [rejected], phonePage: 12);
    expect(spoken('Type the page number'), findsNothing);
  });
}
