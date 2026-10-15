import 'package:book_guard_app/src/screens/monday_first.dart';
import 'package:book_guard_app/src/screens/pace_cells.dart';
import 'package:book_guard_app/src/screens/pace_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/pace_inputs.dart';

void main() {
  Future<void> pump(WidgetTester tester, {String today = '2026-10-15'}) async {
    tester.view.physicalSize = const Size(900, 3200);
    addTearDown(tester.view.reset);
    await pumpTab(
      tester,
      SingleChildScrollView(
        child: PacePanel(
          inputs: inputs(today: today, credits: {'2026-10-13': 17}),
        ),
      ),
    );
  }

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(DatePickerDialog), matching: finder);

  testWidgets("shows this week, the month grid and today's card", (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.byType(DayCell), findsNWidgets(7 + 31));
    expect(find.text('Any day: Thu 15.10'), findsOneWidget);
    expect(find.textContaining('Thu 15.10, today, live'), findsOneWidget);
    expect(find.textContaining('Simulation:'), findsNothing);
    expect(find.text('Reset'), findsNothing);
  });

  testWidgets('tapping a cell selects that day', (tester) async {
    await pump(tester);
    final cell = find.byWidgetPredicate((w) => w is DayCell && w.label == '20');
    await tapVisible(tester, cell);
    await tester.pump();
    expect(find.text('Any day: Tue 20.10'), findsOneWidget);
    final weekCell = find.byWidgetPredicate(
      (w) => w is DayCell && w.label == 'W',
    );
    await tapVisible(tester, weekCell.first);
    await tester.pump();
    expect(find.text('Any day: Wed 14.10'), findsOneWidget);
  });

  testWidgets('the month arrows stop at the plan start and the year end', (
    tester,
  ) async {
    await pump(tester);
    VoidCallback? onPressed(String tooltip) => tester
        .widget<IconButton>(
          find.widgetWithIcon(
            IconButton,
            tooltip == 'Previous month'
                ? Icons.chevron_left
                : Icons.chevron_right,
          ),
        )
        .onPressed;
    expect(onPressed('Previous month'), isNull);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pump();
    expect(find.text('November 2026'), findsOneWidget);
    expect(onPressed('Previous month'), isNotNull);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    expect(find.text('October 2026'), findsOneWidget);
    for (var i = 0; i < 14; i++) {
      await tester.tap(find.byTooltip('Next month'));
      await tester.pump();
    }
    expect(find.text('December 2027'), findsOneWidget);
    expect(onPressed('Next month'), isNull);
  });

  testWidgets('the any-day picker jumps to the picked day and its month', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, find.text('Any day: Thu 15.10'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('20')));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Any day: Tue 20.10'), findsOneWidget);
    expect(find.textContaining('Tue 20.10, projected'), findsOneWidget);
  });

  testWidgets('cancelling the any-day picker changes nothing', (tester) async {
    await pump(tester);
    await tapVisible(tester, find.text('Any day: Thu 15.10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Any day: Thu 15.10'), findsOneWidget);
  });

  testWidgets('the stepper simulates plus and minus 5, Reset clears it', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('0 pages'), findsOneWidget);
    await tapVisible(tester, find.byTooltip('5 pages more'));
    await tester.pump();
    expect(find.text('+5 pages'), findsOneWidget);
    expect(
      find.text('Simulation: +5 pages on Thu 15.10 (display only)'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('5 pages fewer'));
    await tester.tap(find.byTooltip('5 pages fewer'));
    await tester.pump();
    expect(find.text('-5 pages'), findsOneWidget);
    expect(find.textContaining('Simulation: -5 pages'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('0 pages'), findsOneWidget);
    expect(find.textContaining('Simulation:'), findsNothing);
  });

  testWidgets('the simulated day can be moved to another day', (tester) async {
    await pump(tester);
    await tapVisible(tester, find.text('on Thu 15.10'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('24')));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('on Sat 24.10'), findsOneWidget);
    await tapVisible(tester, find.byTooltip('5 pages more'));
    await tester.pump();
    expect(
      find.text('Simulation: +5 pages on Sat 24.10 (display only)'),
      findsOneWidget,
    );
  });

  testWidgets('both date pickers start the week on Monday, as the grid does', (
    tester,
  ) async {
    await pump(tester);
    for (final opener in ['Any day: Thu 15.10', 'on Thu 15.10']) {
      await tapVisible(tester, find.text(opener));
      await tester.pumpAndSettle();
      final monday = tester.getCenter(inDialog(find.text('M'))).dx;
      for (final weekend in inDialog(find.text('S')).evaluate()) {
        expect(
          monday,
          lessThan(tester.getCenter(find.byWidget(weekend.widget)).dx),
        );
      }
      // Thu 1 October sits in the fourth column.
      expect(
        tester.getCenter(inDialog(find.text('1'))).dx,
        greaterThan(tester.getCenter(inDialog(find.text('W'))).dx),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  test('the Monday-first delegate loads synchronously and never reloads', () {
    const delegate = MondayFirstLocalizations.delegate;
    const locale = Locale('pl');
    expect(delegate.isSupported(locale), isTrue);
    expect(delegate.shouldReload(delegate), isFalse);
    expect(
      delegate.load(locale),
      isA<SynchronousFuture<MaterialLocalizations>>(),
    );
    expect(const MondayFirstLocalizations().firstDayOfWeekIndex, 1);
  });

  testWidgets('cancelling the simulation day picker keeps the day', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, find.text('on Thu 15.10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('on Thu 15.10'), findsOneWidget);
  });

  testWidgets('a month that starts on a Monday has no blank cells', (
    tester,
  ) async {
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Next month'));
      await tester.pump();
    }
    expect(find.text('February 2027'), findsOneWidget);
    expect(find.byType(DayCell), findsNWidgets(7 + 28));
  });
}
