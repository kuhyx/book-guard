// Every main screen fits one Pixel 6a screen: nothing scrolls vertically,
// the overflow pages sideways, and the primary actions can be tapped.

import 'package:book_guard_app/src/screens/library_book_screen.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/photos_screen.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:book_guard_app/src/screens/report_dialog.dart';
import 'package:book_guard_app/src/screens/session_screen.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_api.dart';
import 'support/finders_read.dart';
import 'support/fit_support.dart';

void main() {
  testWidgets('Status fits: lock, pace tile, todo and session tiles', (
    tester,
  ) async {
    await openHome(tester, 'status');
    expectNoVerticalScroll(tester);
    expectTappable(tester, find.byIcon(Icons.lock));
    expectTappable(tester, spoken('pace details'));
    // Newest first; the oldest waits behind the all-sessions tile.
    expectTappable(tester, find.text('221-240'));
    expect(find.text('1-20'), findsNothing);
    expectTappable(tester, spoken('all sessions'));
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

  testWidgets('Read fits: session buttons, summary and a photos button', (
    tester,
  ) async {
    await openHome(tester, 'read');
    expectNoVerticalScroll(tester);
    // One session at a time: its summary is the one step, no start or stop.
    expect(find.byType(SummaryPanel), findsOneWidget);
    expectTappable(tester, spoken('Submit summary'));
    expect(spoken('Start reading'), findsNothing);
    expect(spoken('Stop reading'), findsNothing);
    // The photos live on their own screen, not a page of this tab.
    expect(find.byType(PhotoGallery), findsNothing);
    expectTappable(tester, spoken('photos'));
    expect(find.byType(Badge), findsWidgets, reason: 'failed photos dot');
  });

  testWidgets('Photos screen fits: failed strip, paged grid, report', (
    tester,
  ) async {
    await openHome(tester, 'read');
    await tester.tap(spoken('photos'));
    await settle(tester, 60);
    expect(find.byType(PhotosScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing, reason: 'own screen');
    expectNoVerticalScroll(tester);
    expectTappable(tester, spoken('failed photos'));
    expectTappable(tester, spoken('Box the number'));
    expectTappable(tester, find.byKey(const ValueKey('photo-p1.jpg')));
    final report = spoken('This should not fail');
    expectTappable(tester, report);
    await tester.tap(report.first);
    await settle(tester, 20);
    expect(find.byType(ReportDialog), findsOneWidget);
    await tester.tapAt(const Offset(200, 120));
    await settle(tester, 20);
    // Back: the Read tab as it was.
    await tester.tap(spoken('back'));
    await settle(tester, 60);
    expect(find.byType(PhotosScreen), findsNothing);
    expect(find.byType(SummaryPanel), findsOneWidget);
  });

  testWidgets('Gallery fits: 40 photos as a 3-column paged grid', (
    tester,
  ) async {
    pixel6a(tester);
    final api = FakeApi(state: busyState());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: PhotoGallery(api: api, photos: busyState().photos),
          ),
        ),
      ),
    );
    await settle(tester, 10);
    expectNoVerticalScroll(tester);
    Rect at(int i) => tester.getRect(find.byKey(ValueKey('photo-p$i.jpg')));
    expect(at(1).top, at(0).top, reason: '3 in a row');
    expect(at(2).top, at(0).top, reason: '3 in a row');
    expect(at(3).top, greaterThan(at(0).top), reason: 'the 4th wraps');
    final photo = find.byKey(const ValueKey('photo-p1.jpg'));
    expectTappable(tester, photo);
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
    // Swipe page by page to the last photo.
    final last = find.byKey(const ValueKey('photo-p39.jpg'));
    for (var i = 0; i < 5 && last.evaluate().isEmpty; i++) {
      await tester.dragFrom(const Offset(300, 400), const Offset(-300, 0));
      await settle(tester, 40);
    }
    expect(find.byKey(const ValueKey('photo-p0.jpg')), findsNothing);
    expect(last, findsOneWidget);
  });

  testWidgets('Read with the keyboard up for a summary never overflows', (
    tester,
  ) async {
    await openHome(tester, 'read');
    expect(find.byType(SummaryPanel), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    await settle(tester, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Library fits: 3-column colour tiles, paged', (tester) async {
    await openHome(tester, 'library');
    expectNoVerticalScroll(tester);
    Finder tile(int i) =>
        find.byKey(ValueKey('book-97800000000${i.toString().padLeft(2, '0')}'));
    final first = tile(0);
    expectTappable(tester, first);
    expect(
      tester.getRect(tile(1)).left,
      greaterThan(tester.getRect(first).right),
    );
    expect(tester.getRect(tile(2)).top, tester.getRect(first).top);
    expect(tester.getRect(tile(3)).top, greaterThan(tester.getRect(first).top));
    // Colour, not text: no title on a tile, and the tiles differ.
    expect(find.text('A rather long book title number 0'), findsNothing);
    final fills = {
      for (var i = 0; i < 9; i++)
        tester
            .widget<Card>(
              find.descendant(of: tile(i), matching: find.byType(Card)),
            )
            .color,
    };
    expect(fills.length, greaterThan(3));
    expect(tile(29), findsNothing);
    expect(find.byKey(const ValueKey('fit-grid-dot-1')), findsOneWidget);
    // Long-press: the title, the author and the facts.
    await tester.longPress(first);
    await settle(tester, 20);
    final sheet = find.byType(BottomSheet);
    for (final text in ['A rather long book title number 0', 'Author 0']) {
      expect(find.descendant(of: sheet, matching: find.text(text)), findsOne);
    }
    await tester.tapAt(const Offset(200, 120));
    await settle(tester, 20);
    await tester.tap(first);
    await settle(tester, 20);
    expect(find.byType(LibraryBookScreen), findsOneWidget);
  });

  testWidgets('Status offline: the cloud card on top, still no scroll', (
    tester,
  ) async {
    await openHome(tester, 'status', offline: true);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expectNoVerticalScroll(tester);
    expectTappable(tester, spoken('pace details'));
    expectTappable(tester, find.text('221-240'));
    expectTappable(tester, spoken('all sessions'));
  });

  testWidgets('Photos screen offline: grid and failed strip stay', (
    tester,
  ) async {
    await openHome(tester, 'read', offline: true);
    await tester.tap(spoken('photos'));
    await settle(tester, 60);
    expectNoVerticalScroll(tester);
    expectTappable(tester, spoken('failed photos'));
    expectTappable(tester, spoken('Box the number'));
    expectTappable(tester, find.byKey(const ValueKey('photo-p1.jpg')));
  });

  testWidgets('a mouse drag pages the grid (the desktop build)', (
    tester,
  ) async {
    await openHome(tester, 'library');
    await tester.drag(
      find.byKey(const ValueKey('book-9780000000000')),
      const Offset(-300, 0),
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester, 30);
    expect(find.byKey(const ValueKey('book-9780000000029')), findsOneWidget);
  });
}
