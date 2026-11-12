// Every main screen fits one Pixel 6a screen: nothing scrolls vertically,
// the overflow pages sideways, and the primary actions can be tapped.

import 'package:book_guard_app/src/screens/library_book_screen.dart';
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

  testWidgets('Read fits: session buttons, failed photos, paged photo grid', (
    tester,
  ) async {
    await openHome(tester, 'read');
    expectNoVerticalScroll(tester);
    // Start or stop, whichever the journal leaves open.
    expectTappable(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.semanticLabel == 'Start reading' ||
                w.semanticLabel == 'Stop reading'),
      ),
    );
    expect(find.byType(SummaryPanel), findsOneWidget);
    expectTappable(tester, spoken('photos'));
    await tester.tap(spoken('photos'));
    await settle(tester, 10);
    expectNoVerticalScroll(tester);
    expectTappable(tester, spoken('failed photos'));
    expectTappable(tester, spoken('Box the number'));
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
    final report = spoken('This should not fail');
    expectTappable(tester, report);
    await tester.tap(report.first);
    await settle(tester, 20);
    expect(find.byType(ReportDialog), findsOneWidget);
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

  testWidgets('Library fits: 3-column text tiles, paged', (tester) async {
    await openHome(tester, 'library');
    expectNoVerticalScroll(tester);
    final first = find.text('A rather long book title number 0');
    expectTappable(tester, first);
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
    await openHome(tester, 'status', offline: true);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expectNoVerticalScroll(tester);
    expectTappable(tester, spoken('pace details'));
    expectTappable(tester, find.text('221-240'));
    expectTappable(tester, spoken('all sessions'));
  });

  testWidgets('Read photos offline: grid, failed strip and queue stay', (
    tester,
  ) async {
    await openHome(tester, 'read', offline: true);
    await tester.tap(spoken('photos'));
    await settle(tester, 10);
    expect(find.byIcon(Icons.cloud_off), findsNothing);
    expectNoVerticalScroll(tester);
    expectTappable(tester, spoken('failed photos'));
    expectTappable(tester, spoken('Box the number'));
    expectTappable(tester, find.byKey(const ValueKey('photo-p1.jpg')));
    // The queue badge in the app bar counts what waits for the PC.
    expect(find.byType(Badge), findsWidgets);
  });

  testWidgets('a mouse drag pages the grid (the desktop build)', (
    tester,
  ) async {
    await openHome(tester, 'library');
    await tester.drag(
      find.text('A rather long book title number 0'),
      const Offset(-300, 0),
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester, 30);
    expect(find.text('A rather long book title number 29'), findsOneWidget);
  });
}
