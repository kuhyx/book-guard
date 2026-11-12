// Every main screen fits one Pixel 6a screen: nothing scrolls vertically,
// the overflow pages sideways, and the primary actions can be tapped.
import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/app.dart';
import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:book_guard_app/src/screens/report_dialog.dart';
import 'package:book_guard_app/src/screens/session_screen.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:book_guard_app/src/snapshot.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';
import 'support/fake_reader.dart';
import 'support/finders_read.dart';
import 'support/pace_inputs.dart';
import 'support/states.dart';

/// Pixel 6a: 1080x2400 px at 2.625, status bar 132 px, gesture bar 63 px.
void _pixel6a(WidgetTester tester) {
  const padding = FakeViewPadding(top: 132, bottom: 63);
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.625
    ..padding = padding
    ..viewPadding = padding;
  addTearDown(tester.view.reset);
}

/// A full month: pace inputs, todo lines and a dozen sessions.
GuardState _busyState() => GuardState.fromJson(_busyJson());

/// [_busyState] as the PC writes it.
Map<String, dynamic> _busyJson() => {
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
Map<String, dynamic> _library() => {
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
Future<FakeApi> _open(
  WidgetTester tester,
  String tab, {
  bool offline = false,
}) async {
  _pixel6a(tester);
  final api = FakeApi(state: _busyState());
  if (offline) {
    // The PC out of reach: only the snapshot kept on the phone.
    await api.store.write(
      snapshotFile,
      utf8.encoder.convert(jsonEncode(_busyJson())),
    );
    api
      ..fetchError = const DavException('Reading/state.json', 0)
      ..offline = true;
  }
  await api.dav.put(
    'Reading/library.json',
    utf8.encoder.convert(jsonEncode(_library())),
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
void _expectNoVerticalScroll(WidgetTester tester) {
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
void _expectTappable(WidgetTester tester, Finder finder) {
  expect(finder.hitTestable(), findsWidgets, reason: '$finder not tappable');
  final nav = tester.getRect(find.byType(NavigationBar));
  final rect = tester.getRect(finder.first);
  expect(rect.bottom, lessThanOrEqualTo(nav.top + 0.5), reason: '$finder');
  expect(rect.top, greaterThanOrEqualTo(132 / 2.625), reason: '$finder');
}

void main() {
  testWidgets('Status fits: lock, pace tile, todo and session tiles', (
    tester,
  ) async {
    await _open(tester, 'status');
    _expectNoVerticalScroll(tester);
    _expectTappable(tester, find.byIcon(Icons.lock));
    _expectTappable(tester, spoken('pace details'));
    // Newest first; the oldest waits behind the all-sessions tile.
    _expectTappable(tester, find.text('221-240'));
    expect(find.text('1-20'), findsNothing);
    _expectTappable(tester, spoken('all sessions'));
    // The pace cells sit in a sheet behind the pace tile.
    await tester.tap(spoken('pace details'));
    await settle(tester, 20);
    expect(spoken('previous month'), findsOneWidget);
    await tester.tapAt(const Offset(200, 120));
    await settle(tester, 20);
    await tester.tap(spoken('all sessions'));
    await settle(tester, 20);
    final oldest = find.text('1-20');
    await tester.scrollUntilVisible(
      oldest,
      200,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(oldest);
    await settle(tester, 20);
    expect(find.byType(SessionScreen), findsOneWidget);
  });

  testWidgets('Read fits: session buttons, failed photos, paged photo grid', (
    tester,
  ) async {
    await _open(tester, 'read');
    _expectNoVerticalScroll(tester);
    // Start or stop, whichever the journal leaves open.
    _expectTappable(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.semanticLabel == 'Start reading' ||
                w.semanticLabel == 'Stop reading'),
      ),
    );
    expect(find.byType(SummaryPanel), findsOneWidget);
    _expectTappable(tester, spoken('photos'));
    await tester.tap(spoken('photos'));
    await settle(tester, 10);
    _expectNoVerticalScroll(tester);
    _expectTappable(tester, spoken('failed photos'));
    _expectTappable(tester, spoken('Box the number'));
    final photo = find.byKey(const ValueKey('photo-p1.jpg'));
    _expectTappable(tester, photo);
    // The rest of the 40 photos page sideways.
    expect(find.byKey(const ValueKey('photo-p39.jpg')), findsNothing);
    expect(find.byKey(const ValueKey('fit-grid-dot-1')), findsOneWidget);
    // Long-press: the time and the reject mark.
    await tester.longPress(photo);
    await settle(tester, 20);
    final t = DateTime.utc(2026, 9, 26, 10, 1).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(
        of: sheet,
        matching: find.text(
          '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.byType(RejectBadge)),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(200, 120));
    await settle(tester, 20);
    final report = spoken('This should not fail');
    _expectTappable(tester, report);
    await tester.tap(report.first);
    await settle(tester, 20);
    expect(find.byType(ReportDialog), findsOneWidget);
  });

  testWidgets('Read with the keyboard up for a summary never overflows', (
    tester,
  ) async {
    await _open(tester, 'read');
    expect(find.byType(SummaryPanel), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    await settle(tester, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Library fits: 3-column text tiles, paged', (tester) async {
    await _open(tester, 'library');
    _expectNoVerticalScroll(tester);
    final first = find.text('A rather long book title number 0');
    _expectTappable(tester, first);
    final a = tester.getRect(first);
    final b = tester.getRect(find.text('A rather long book title number 1'));
    expect(b.left, greaterThan(a.right), reason: 'tiles share a row');
    expect(find.text('A rather long book title number 29'), findsNothing);
    expect(find.byKey(const ValueKey('fit-grid-dot-1')), findsOneWidget);
    await tester.longPress(first);
    await settle(tester, 20);
    expect(find.text('Author 0'), findsOneWidget);
    await tester.tapAt(const Offset(200, 120));
    await settle(tester, 20);
    await tester.tap(first);
    await settle(tester, 20);
    expect(find.byType(LibraryBookScreen), findsOneWidget);
  });

  testWidgets('Status offline: the cloud card on top, still no scroll', (
    tester,
  ) async {
    await _open(tester, 'status', offline: true);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    _expectNoVerticalScroll(tester);
    _expectTappable(tester, spoken('pace details'));
    _expectTappable(tester, find.text('221-240'));
    _expectTappable(tester, spoken('all sessions'));
  });

  testWidgets('a mouse drag pages the grid (the desktop build)', (
    tester,
  ) async {
    await _open(tester, 'library');
    await tester.drag(
      find.text('A rather long book title number 0'),
      const Offset(-300, 0),
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester, 30);
    expect(find.text('A rather long book title number 29'), findsOneWidget);
  });
}
