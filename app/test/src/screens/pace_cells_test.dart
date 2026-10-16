import 'package:book_guard_app/src/pace/day_views.dart';
import 'package:book_guard_app/src/screens/pace_cells.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

DayView view({
  DayKind kind = DayKind.past,
  int credited = 22,
  int required = 17,
  int assumed = 22,
  bool free = false,
  bool sick = false,
  bool oldRule = false,
  bool beforeQuotas = false,
  int simulated = 0,
  int line = 100,
  int pages = 60,
  int debt = 0,
  int credit = 0,
}) => DayView(
  day: DateTime.utc(2026, 10, 15),
  kind: kind,
  pace: DayPace(
    month: DateTime.utc(2026, 10),
    target: 1000,
    carriedDebt: debt,
    carriedCredit: credit,
    pages: pages,
    line: line,
    required: required,
  ),
  credited: credited,
  assumed: assumed,
  free: free,
  sick: sick,
  oldRule: oldRule,
  beforeQuotas: beforeQuotas,
  simulated: simulated,
);

void main() {
  test('names of days and months', () {
    expect(shortDay(DateTime.utc(2026, 10, 15)), 'Thu 15.10');
    expect(shortDay(DateTime.utc(2026, 1, 4)), 'Sun 04.01');
    expect(monthTitle(DateTime.utc(2026, 10)), 'October 2026');
    expect(weekdayInitials, ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
  });

  group('cellText and met', () {
    test('each kind of day reads differently', () {
      expect(cellText(view(beforeQuotas: true, free: true)), '-');
      expect(cellText(view(free: true, oldRule: true)), 'free');
      expect(cellText(view(oldRule: true)), 'old 22');
      expect(cellText(view(kind: DayKind.future)), '17');
      expect(cellText(view()), '22/17');
      expect(cellText(view(kind: DayKind.today)), '22/17');
    });

    test('the simulated day shows its simulated total', () {
      final today = view(kind: DayKind.today, assumed: 27, simulated: 5);
      expect(cellText(today), '27/17');
      expect(
        cellText(view(kind: DayKind.future, assumed: 7, simulated: -10)),
        '7/17',
      );
      expect(cellText(view(free: true, assumed: 5, simulated: 5)), '5/17');
      expect(met(today), isTrue);
      expect(
        met(view(kind: DayKind.today, assumed: 12, simulated: -10)),
        isFalse,
      );
    });

    test('met needs a quota day that is not in the future', () {
      expect(met(view()), isTrue);
      expect(met(view(credited: 16)), isFalse);
      expect(met(view(kind: DayKind.future)), isFalse);
      expect(met(view(oldRule: true)), isFalse);
      expect(met(view(beforeQuotas: true)), isFalse);
    });
  });

  group('dayLines', () {
    test('before the first quota day', () {
      expect(dayLines(view(beforeQuotas: true)), [
        'Thu 15.10: no page quota yet',
      ]);
    });

    test('before the switch names the old rule', () {
      expect(dayLines(view(oldRule: true)), [
        oldRuleText,
        'Credited that day: 22 pages',
      ]);
    });

    test('a past day, behind, with carried debt', () {
      expect(dayLines(view(debt: 30)), [
        'Thu 15.10, as it stood that morning',
        'Requirement: 17 pages; credited 22',
        'Line at the start of the day 100; read 60 (40 behind)',
        'Month target 1000 (carried debt 30)',
      ]);
    });

    test('today on pace, with carried credit', () {
      final lines = dayLines(view(kind: DayKind.today, line: 50, credit: 20));
      expect(lines[0], 'Thu 15.10, today, live');
      expect(lines[2], contains('read 60 (on pace)'));
      expect(lines[3], 'Month target 1000 (carried credit 20)');
    });

    test('a future day shows the assumption, or the simulation', () {
      final plain = dayLines(view(kind: DayKind.future, assumed: 17));
      expect(plain[0], contains('projected'));
      expect(plain[1], 'Requirement: 17 pages');
      expect(plain[2], 'Assumed read: 17');
      final plus = dayLines(
        view(kind: DayKind.future, assumed: 57, simulated: 40),
      );
      expect(plus[2], 'Simulated: 57 read (+40)');
      final minus = dayLines(view(assumed: 0, simulated: -17));
      expect(minus[2], 'Simulated: 0 read (-17)');
    });

    test('a sick day asks nothing and says so', () {
      expect(cellText(view(sick: true, required: 0)), 'sick');
      expect(
        dayLines(view(sick: true))[1],
        "Sick day: asks nothing, its share is off the month's target",
      );
    });

    test('a free day asks nothing', () {
      expect(dayLines(view(free: true))[1], 'Free day: asks nothing');
    });
  });

  group('DayCell', () {
    Future<int> pumpCell(
      WidgetTester tester,
      DayView v, {
      bool selected = false,
    }) async {
      var taps = 0;
      await pumpTab(
        tester,
        Row(
          children: [
            Expanded(
              child: DayCell(
                view: v,
                label: '15',
                selected: selected,
                onTap: () => taps++,
              ),
            ),
          ],
        ),
      );
      await tester.tap(find.text('15'));
      return taps;
    }

    BoxDecoration decoration(WidgetTester tester) =>
        tester.widget<Container>(find.byType(Container).first).decoration!
            as BoxDecoration;

    testWidgets('a met day is green, taps select it', (tester) async {
      expect(await pumpCell(tester, view()), 1);
      expect(find.text('22/17'), findsOneWidget);
      expect(decoration(tester).color, isNotNull);
    });

    testWidgets('a missed past day is red, a selected one is outlined', (
      tester,
    ) async {
      await pumpCell(tester, view(credited: 3), selected: true);
      final box = decoration(tester);
      expect(box.color, isNotNull);
      expect((box.border! as Border).top.width, 2);
    });

    testWidgets('today, free, future and simulated days are not filled', (
      tester,
    ) async {
      await pumpCell(tester, view(kind: DayKind.today, credited: 1));
      expect(decoration(tester).color, isNull);
      await pumpCell(tester, view(free: true, credited: 3));
      expect(decoration(tester).color, isNull);
      await pumpCell(tester, view(kind: DayKind.future, simulated: 5));
      expect(decoration(tester).color, isNull);
      final text = tester.widget<Text>(find.text('22/17'));
      expect(text.style?.fontWeight, FontWeight.bold);
    });
  });
}
