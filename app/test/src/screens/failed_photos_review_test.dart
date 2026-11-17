import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/fake_reader.dart';
import '../../support/finders_read.dart';

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  testWidgets('the keypad on the review screen sends a typed number', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await api.store.write('photos/start_a.jpg', Uint8List.fromList([1]));
    final base = GuardState.fromJson(const {});
    await pumpTab(
      tester,
      SingleChildScrollView(
        child: FailedPhotos(
          api: api,
          state: GuardState(
            locked: base.locked,
            reason: base.reason,
            book: base.book,
            pace: base.pace,
            todo: base.todo,
            sessions: base.sessions,
            openStart: base.openStart,
            generatedAt: base.generatedAt,
            photos: [
              reading(name: 'start_a.jpg', kind: 'other', status: 'rejected'),
            ],
          ),
          journal: [
            JournalEntry(
              name: 'start_a.jpg',
              label: 'start',
              sha: 'f' * 64,
              takenAt: DateTime.utc(2026, 10, 3, 12, 27),
              page: 7,
            ),
          ],
          reader: FakeReader(
            fakeScan([(7, (left: 1, top: 50, right: 5, bottom: 55))]),
          ),
          onChanged: () async {},
        ),
      ),
    );
    await settle(tester, 10);
    await tester.tap(find.byIcon(Icons.crop_free));
    await settle(tester, 10);
    await tester.tap(spoken('Type the page number'));
    await settle(tester, 10);
    await tester.enterText(find.byType(TextField), '29');
    await tester.tap(spoken('Send the typed page number'));
    await settle(tester, 10);
    final sent = api.sent.single;
    expect(sent.type, 'type_page');
    expect(sent.body, {'photo': 'start_a.jpg', 'page': 29});
  });
}
