import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
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

  testWidgets('the box is drawn while dragging', (tester) async {
    final reader = FakeReader(fakeScan([]), boxed: 7);
    await pump(tester, reader, state: readingState());
    await open(tester, 'Start reading');
    final photo = tester.getTopLeft(find.byType(Image));
    final k = _scale(tester);
    final gesture = await tester.startGesture(photo + const Offset(15, 50) * k);
    await gesture.moveBy(const Offset(10, 6) * k);
    await tester.pump();
    await gesture.moveBy(const Offset(1, 1));
    await tester.pump();
    await gesture.up();
    await settle(tester, 10);
    expect(find.text('Page 7?'), findsOneWidget);
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
    await open(tester, 'Start reading');
    expect(find.text('Page 51?'), findsOneWidget);
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
    await open(tester, 'Start reading');
    expect(find.text('Page 51?'), findsOneWidget);
  });

  testWidgets('a Claude outage is explained next to the summary', (
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
    expect(find.textContaining('unavailable since 12:27'), findsOneWidget);
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
    expect(
      find.text('1 photo(s) taken here are not read by the PC yet.'),
      findsOneWidget,
    );
    expect(
      find.text('Reading since p. 51 - photograph the page where you stop.'),
      findsOneWidget,
    );
  });
}

/// Preview pixels -> logical pixels, as the review screen laid them out.
double _scale(WidgetTester tester) =>
    tester.getSize(find.byType(Image)).width / 40;
