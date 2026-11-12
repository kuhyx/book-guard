import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/grader_note.dart';
import 'package:book_guard_app/src/screens/read_support.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/fake_reader.dart';
import '../../support/finders_read.dart';
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

  Future<void> open(WidgetTester tester, Finder button) async {
    await tapVisible(tester, button);
    await settle(tester, 10);
  }

  testWidgets('the box is drawn while dragging', (tester) async {
    final reader = FakeReader(fakeScan([]), boxed: 7);
    await pump(tester, reader, state: readingState());
    await open(tester, spoken('Start reading'));
    final photo = tester.getTopLeft(find.byType(Image));
    final k = _scale(tester);
    final gesture = await tester.startGesture(photo + const Offset(15, 50) * k);
    await gesture.moveBy(const Offset(10, 6) * k);
    await tester.pump();
    await gesture.moveBy(const Offset(1, 1));
    await tester.pump();
    await gesture.up();
    await settle(tester, 10);
    expect(chosenPage(7), findsOneWidget);
  });

  testWidgets("a start is judged against this phone's last stop", (
    tester,
  ) async {
    final reader = FakeReader(
      fakeScan([
        (3, (left: 18, top: 4, right: 22, bottom: 8)),
        (51, (left: 17, top: 54, right: 23, bottom: 58)),
      ]),
    );
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
        journal: [
          JournalEntry(
            name: 'stop_x.jpg',
            label: 'stop',
            sha: 'a' * 64,
            takenAt: DateTime.utc(2026, 10, 3),
            page: 51,
            isbn: '9788368380002', // readingState()'s book
          ),
          JournalEntry(
            name: 'stop_y.jpg',
            label: 'stop',
            sha: 'b' * 64,
            takenAt: DateTime.utc(2026, 10, 3),
          ),
        ],
        photoSource: ({required camera}) async =>
            XFile.fromData(_bytes, path: '/DCIM/IMG.jpg'),
      ),
    );
    await open(tester, spoken('Start reading'));
    expect(chosenPage(51), findsOneWidget);
  });

  testWidgets('the newest PC session is the last end', (tester) async {
    final reader = FakeReader(
      fakeScan([
        (3, (left: 18, top: 4, right: 22, bottom: 8)),
        (51, (left: 17, top: 54, right: 23, bottom: 58)),
      ]),
    );
    final state = GuardState.fromJson({
      'sessions': [
        {
          'id': 'new',
          'start_page': 7,
          'end_page': 51,
          'status': 'credited',
          'started_at': '2026-10-02T19:05:00Z',
        },
        {'id': 'undated', 'start_page': 1, 'end_page': 2, 'status': 'credited'},
        {
          'id': 'old',
          'start_page': 1,
          'end_page': 4,
          'status': 'credited',
          'started_at': '2026-09-26T10:00:00Z',
        },
      ],
    });
    await pump(tester, reader, state: state);
    await open(tester, spoken('Start reading'));
    expect(chosenPage(51), findsOneWidget);
  });

  testWidgets('a Claude outage is explained next to a summary that waits', (
    tester,
  ) async {
    final state = GuardState.fromJson({
      'claude_down_since': '2026-10-03T12:27:00',
      'sessions': [
        {
          'id': 'session:q',
          'start_page': 51,
          'end_page': 103,
          'status': 'needs-quiz',
        },
      ],
    });
    await pump(tester, FakeReader(null), state: state);
    await settle(tester);
    expect(find.byType(GraderNoteChip), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await api.markGrading('session:q'); // sent, no verdict yet
    await pump(tester, FakeReader(null), state: state);
    await settle(tester);
    expect(find.byType(GraderNoteChip), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GraderNoteChip),
        matching: find.text('03.10 12:27'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('photos the PC has not read yet are counted', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final journal = [
      JournalEntry(
        name: 'start_a.jpg',
        label: 'start',
        sha: 'a' * 64,
        takenAt: DateTime.utc(2026, 10, 3),
        page: 51,
      ),
    ];
    await pumpTab(
      tester,
      ReadTab(
        api: api,
        state: readingState(),
        desktop: false,
        onChanged: () async {},
        local: localView(readingState(), journal),
        journal: journal,
      ),
    );
    // One photo waits (outbox + 1); reading since page 51 (stop + 51).
    expect(
      find.descendant(of: find.byType(SessionPrompt), matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: buttonSpoken('Stop reading'),
        matching: find.text('51'),
      ),
      findsOneWidget,
    );
  });
}

/// Preview pixels -> logical pixels, as the review screen laid them out.
double _scale(WidgetTester tester) =>
    tester.getSize(find.byType(Image)).width / 40;
