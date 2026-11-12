// Shared by the fit-to-screen tests: Pixel 6a geometry, a busy snapshot,
// a 30-book library, and the two assertions the tests make.
import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/app.dart';
import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:book_guard_app/src/snapshot.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';
import 'fake_reader.dart';
import 'finders_read.dart';
import 'pace_inputs.dart';
import 'states.dart';

/// Pixel 6a: 1080x2400 px at 2.625, status bar 132 px, gesture bar 63 px.
void pixel6a(WidgetTester tester) {
  const padding = FakeViewPadding(top: 132, bottom: 63);
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.625
    ..padding = padding
    ..viewPadding = padding;
  addTearDown(tester.view.reset);
}

/// A full month: pace inputs, todo lines and a dozen sessions.
GuardState busyState() => GuardState.fromJson(busyJson());

/// [busyState] as the PC writes it.
Map<String, dynamic> busyJson() => {
  ...fullState(),
  'pace_inputs': inputsJson(),
  'todo': ['Photograph page 42', 'Write the summary of 21-40', 'Read 20'],
  'sessions': [
    for (var i = 0; i < 12; i++)
      {
        'id': 'session:s$i-e$i',
        'start_page': i * 20 + 1,
        'end_page': i * 20 + 20,
        'pages': 20,
        'minutes': 30,
        // The newest waits for its summary, the one before for a check.
        'status': switch (i) {
          11 => 'needs-quiz',
          10 => 'needs-check-photo',
          _ => 'credited',
        },
        'check_page': i * 20 + 5,
        'detail': 'credited $i',
      },
  ],
  'photos': [
    for (var i = 0; i < 40; i++)
      {
        'name': 'p$i.jpg',
        'file': 'processed/0123456789ab-p$i.jpg',
        'thumb': 'thumbs/p$i.jpg',
        'kind': 'page',
        'page': 100 - i,
        'status': i.isEven ? 'ok' : 'rejected',
        'reason': i.isEven ? '' : 'no page number',
        'taken_at': '2026-09-26T10:${(i % 60).toString().padLeft(2, '0')}:00Z',
      },
  ],
};

/// Thirty books, as the PC writes `library.json`.
Map<String, dynamic> fitLibrary() => {
  'books': [
    for (var i = 0; i < 30; i++)
      {
        'isbn': '97800000000${i.toString().padLeft(2, '0')}',
        'title': 'A rather long book title number $i',
        'author': 'Author $i',
        'status': i == 0 ? 'reading' : (i.isEven ? 'finished' : 'unread'),
        'pages': '${200 + i}',
        'current': i == 0,
      },
  ],
};

/// The home screen at Pixel 6a size, with [tab] (nav bar spoken name) open.
Future<FakeApi> openHome(
  WidgetTester tester,
  String tab, {
  bool offline = false,
}) async {
  pixel6a(tester);
  final api = FakeApi(state: busyState());
  if (offline) {
    // The PC out of reach: only the snapshot kept on the phone.
    await api.store.write(
      snapshotFile,
      utf8.encoder.convert(jsonEncode(busyJson())),
    );
    api
      ..fetchError = const DavException('Reading/state.json', 0)
      ..offline = true;
  }
  await api.dav.put(
    'Reading/library.json',
    utf8.encoder.convert(jsonEncode(fitLibrary())),
  );
  // The newest is the PC's rejected p1.jpg (box again); the rest the phone
  // could not read. Every one is kept on the phone, so each can be reported.
  for (var i = 0; i < 3; i++) {
    final name = i == 2 ? 'p1.jpg' : 'failed$i.jpg';
    await api.store.write('photos/$name', Uint8List.fromList([1, 2, 3]));
    await api.journal.add(
      JournalEntry(
        name: name,
        label: 'start',
        sha: '$i' * 64,
        takenAt: DateTime.utc(2026, 9, 26, 11, i),
      ),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      scrollBehavior: appScrollBehavior,
      home: HomeScreen(
        api: api,
        desktop: false,
        reader: FakeReader(null),
        refreshEvery: const Duration(hours: 1),
      ),
    ),
  );
  await settle(tester, 10);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: spoken(tab)),
  );
  await settle(tester, 10);
  return api;
}

/// No vertical scrollable on screen has anything to scroll.
void expectNoVerticalScroll(WidgetTester tester) {
  final states = tester.stateList<ScrollableState>(find.byType(Scrollable));
  for (final s in states) {
    if (s.position.axis != Axis.vertical) continue;
    expect(
      s.position.maxScrollExtent,
      lessThanOrEqualTo(0),
      reason:
          'vertical scroll in ${s.widget.runtimeType} '
          'under ${s.context.widget}',
    );
  }
}

/// [finder] is on screen, above the nav bar, and takes a tap.
void expectTappable(WidgetTester tester, Finder finder) {
  expect(finder.hitTestable(), findsWidgets, reason: '$finder not tappable');
  final nav = tester.getRect(find.byType(NavigationBar));
  final rect = tester.getRect(finder.first);
  expect(rect.bottom, lessThanOrEqualTo(nav.top + 0.5), reason: '$finder');
  expect(rect.top, greaterThanOrEqualTo(132 / 2.625), reason: '$finder');
}
