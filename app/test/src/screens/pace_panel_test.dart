import 'package:book_guard_app/src/screens/day_card.dart';
import 'package:book_guard_app/src/screens/icon_date_dialog.dart';
import 'package:book_guard_app/src/screens/pace_cells.dart';
import 'package:book_guard_app/src/screens/pace_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_a.dart';
import '../../support/no_letters.dart';
import '../../support/no_words.dart';
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
      find.descendant(of: find.byType(IconDateDialog), matching: finder);

  PickerDay pickerDay(WidgetTester tester, int day) => tester.widget(
    find.byWidgetPredicate((w) => w is PickerDay && w.day == day),
  );

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(inDialog(find.byIcon(Icons.check)));
    await tester.pumpAndSettle();
  }

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(inDialog(find.byIcon(Icons.close)));
    await tester.pumpAndSettle();
  }

  /// The month grid's cell for [day] of October 2026 (the week row, which
  /// comes first, holds the 12th to the 18th).
  Finder cell(int day, {int month = 10}) => find.byWidgetPredicate(
    (w) => w is DayCell && w.view.day == DateTime.utc(2026, month, day),
  );

  /// The "any day" button, then the simulation's day button.
  Finder dayButton(String text) => find.widgetWithText(OutlinedButton, text);

  testWidgets("shows this week, the month grid and today's card", (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('10 · 2026'), findsOneWidget);
    expect(find.byType(DayCell), findsNWidgets(7 + 31));
    expect(find.byType(WeekdayDot), findsNWidgets(7 + 7));
    expect(dayButton('15.10'), findsNWidgets(2));
    expect(find.byType(DayDetails), findsOneWidget);
    expect(find.byIcon(Icons.today), findsOneWidget);
    expect(find.byIcon(Icons.science), findsOneWidget);
    expect(iconLabeled('reset'), findsNothing);
    expectNoWords(tester);
  });

  testWidgets('tapping a cell selects that day', (tester) async {
    await pump(tester);
    await tapVisible(tester, cell(20));
    await tester.pump();
    expect(
      tester.widget<DayDetails>(find.byType(DayDetails)).view.day,
      DateTime.utc(2026, 10, 20),
    );
    expect(dayButton('20.10'), findsOneWidget);
    await tapVisible(tester, cell(14).first);
    await tester.pump();
    expect(dayButton('14.10'), findsOneWidget);
  });

  testWidgets('the month arrows stop at the plan start and the year end', (
    tester,
  ) async {
    await pump(tester);
    VoidCallback? onPressed(String label) => tester
        .widget<IconButton>(
          find.ancestor(
            of: iconLabeled(label),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed;
    expect(onPressed('previous month'), isNull);
    await tester.tap(iconLabeled('next month'));
    await tester.pump();
    expect(find.text('11 · 2026'), findsOneWidget);
    expect(onPressed('previous month'), isNotNull);
    await tester.tap(iconLabeled('previous month'));
    await tester.pump();
    expect(find.text('10 · 2026'), findsOneWidget);
    for (var i = 0; i < 14; i++) {
      await tester.tap(iconLabeled('next month'));
      await tester.pump();
    }
    expect(find.text('12 · 2027'), findsOneWidget);
    expect(onPressed('next month'), isNull);
  });

  testWidgets('the any-day picker jumps to the picked day and its month', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, dayButton('15.10').first);
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('20')));
    await tester.pumpAndSettle();
    expect(pickerDay(tester, 20).selected, isTrue);
    expect(find.byType(IconDateDialog), findsOneWidget, reason: 'tap selects');
    await confirm(tester);
    expect(find.byType(IconDateDialog), findsNothing);
    expect(dayButton('20.10'), findsOneWidget);
    expect(
      tester.widget<DayDetails>(find.byType(DayDetails)).view.day,
      DateTime.utc(2026, 10, 20),
    );
  });

  testWidgets('both day pickers paint no words', (tester) async {
    await pump(tester);
    for (final last in [false, true]) {
      final opener = last ? dayButton('15.10').last : dayButton('15.10').first;
      await tapVisible(tester, opener);
      await tester.pumpAndSettle();
      expectNoLetters(
        tester,
        find.byType(IconDateDialog),
        spoken: [Icons.check, Icons.close],
      );
      // Dismissing (a tap outside) is a cancel too.
      await tester.tap(inDialog(find.text('20')));
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.byType(IconDateDialog), findsNothing);
      expect(dayButton('15.10'), findsNWidgets(2));
    }
  });

  testWidgets('cancelling the any-day picker changes nothing', (tester) async {
    await pump(tester);
    await tapVisible(tester, dayButton('15.10').first);
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('20')));
    await cancel(tester);
    expect(dayButton('15.10'), findsNWidgets(2));
  });

  testWidgets('the stepper simulates plus and minus 5, reset clears it', (
    tester,
  ) async {
    await pump(tester);
    final stepper = find.descendant(
      of: find.byType(Card).last,
      matching: find.text('0'),
    );
    expect(stepper, findsOneWidget);
    await tapVisible(tester, iconLabeled('5 pages more'));
    await tester.pump();
    expect(find.text('+5'), findsNWidgets(2)); // the stepper and the banner
    // The banner, the stepper and the selected day's simulated total.
    expect(find.byIcon(Icons.science), findsNWidgets(3));
    expect(iconLabeled('reset'), findsOneWidget);
    await tester.tap(iconLabeled('5 pages fewer'));
    await tester.tap(iconLabeled('5 pages fewer'));
    await tester.pump();
    expect(find.text('-5'), findsNWidgets(2));
    expectNoWords(tester);
    await tester.tap(iconLabeled('reset'));
    await tester.pump();
    expect(stepper, findsOneWidget);
    expect(find.byIcon(Icons.science), findsOneWidget);
  });

  testWidgets('the simulated day can be moved to another day', (tester) async {
    await pump(tester);
    await tapVisible(tester, dayButton('15.10').last);
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('24')));
    await confirm(tester);
    expect(dayButton('24.10'), findsOneWidget);
    await tapVisible(tester, iconLabeled('5 pages more'));
    await tester.pump();
    // The banner carries the day the simulation sits on.
    expect(find.text('24.10'), findsNWidgets(2));
  });

  testWidgets('the simulation day picker starts at today', (tester) async {
    await pump(tester);
    await tapVisible(tester, dayButton('15.10').last);
    await tester.pumpAndSettle();
    expect(pickerDay(tester, 14).enabled, isFalse);
    expect(pickerDay(tester, 15).enabled, isTrue);
    await tester.tap(inDialog(find.text('14')));
    await confirm(tester);
    expect(dayButton('15.10'), findsNWidgets(2));
  });

  testWidgets('cancelling the simulation day picker keeps the day', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, dayButton('15.10').last);
    await tester.pumpAndSettle();
    await cancel(tester);
    expect(dayButton('15.10'), findsNWidgets(2));
  });

  testWidgets('a month that starts on a Monday has no blank cells', (
    tester,
  ) async {
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(iconLabeled('next month'));
      await tester.pump();
    }
    expect(find.text('02 · 2027'), findsOneWidget);
    expect(find.byType(DayCell), findsNWidgets(7 + 28));
  });
}
