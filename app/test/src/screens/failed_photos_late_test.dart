import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/fake_reader.dart';
import '../../support/finders_read.dart';

// The start stored on the phone from 2026-10-27 and sent on 2026-11-22: the
// PC rejected it as late, so it may only become a kept page photo or go.
final PhotoInfo _late = reading(
  name: 'start_a.jpg',
  kind: 'other',
  page: null,
  status: 'rejected',
  reason: 'uploaded more than 7 days after it was taken',
);

GuardState _state() {
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
    photos: [_late],
  );
}

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await api.store.write('photos/start_a.jpg', Uint8List.fromList([1]));
    await pumpTab(
      tester,
      SingleChildScrollView(
        child: FailedPhotos(
          api: api,
          state: _state(),
          journal: [
            JournalEntry(
              name: 'start_a.jpg',
              label: 'start',
              sha: 'f' * 64,
              takenAt: DateTime.utc(2026, 10, 27, 19, 15),
              page: 473,
            ),
          ],
          reader: FakeReader(
            fakeScan([(473, (left: 17, top: 54, right: 23, bottom: 58))]),
          ),
          onChanged: () async {},
        ),
      ),
    );
    await settle(tester, 10);
  }

  testWidgets('a late photo offers only keep and delete', (tester) async {
    await pump(tester);
    expect(spoken('Box the number'), findsNothing);
    expect(spoken('Type the page number'), findsNothing);
    expect(spoken('This should not fail'), findsNothing);
    expect(spoken('Dismiss'), findsOneWidget);
    await tester.tap(spoken('Keep as a page photo'));
    await settle(tester, 10);
    // The keypad holds the 473 the phone read: one tap keeps it.
    await tester.tap(spoken('Send the typed page number'));
    await settle(tester, 10);
    expect(api.photos.keys, ['kept_start_a.jpg']);
    expect(api.notes['kept_start_a.jpg']?.page, 473);
    expect(api.sent, isEmpty); // no type_page / box for the late copy
    await settle(tester, 30);
    expect(find.text('473'), findsNothing); // the card is gone
  });
}
