import 'package:book_guard_app/src/pace/day_views.dart';
import 'package:book_guard_app/src/screens/day_card.dart';
import 'package:book_guard_app/src/screens/icon_num.dart';
import 'package:book_guard_app/src/screens/pace_cells.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/day_view_fixture.dart';
import '../../support/fake_api.dart';
import '../../support/finders_a.dart';
import '../../support/no_words.dart';

void main() {
  test('days and months are numerals', () {
    expect(shortDay(DateTime.utc(2026, 10, 15)), '15.10');
    expect(shortDay(DateTime.utc(2026, 1, 4)), '04.01');
    expect(monthTitle(DateTime.utc(2026, 10)), '10 · 2026');
    expect(isWeekend(DateTime.utc(2026, 10, 17)), isTrue);
    expect(isWeekend(DateTime.utc(2026, 10, 18)), isTrue);
    expect(isWeekend(DateTime.utc(2026, 10, 19)), isFalse);
  });

  group('cellMark and met', () {
    test('each kind of day reads differently', () {
      expect(cellMark(view(beforeQuotas: true, free: true)).number, '-');
      expect(cellMark(view(free: true, oldRule: true)).icon, freeGlyph);
      expect(cellMark(view(oldRule: true)), (
        icon: Icons.history,
        number: '22',
      ));
      expect(cellMark(view(kind: DayKind.future)).number, '17');
      expect(cellMark(view()).number, '22/17');
      expect(cellMark(view(kind: DayKind.today)).number, '22/17');
      expect(cellMark(view(sick: true, required: 0)).icon, sickGlyph);
    });

    test('the simulated day shows its simulated total', () {
      final today = view(kind: DayKind.today, assumed: 27, simulated: 5);
      expect(cellMark(today).number, '27/17');
      expect(
        cellMark(view(kind: DayKind.future, assumed: 7, simulated: -10)).number,
        '7/17',
      );
      expect(
        cellMark(view(free: true, assumed: 5, simulated: 5)).number,
        '5/17',
      );
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

    test('missed is a past quota day that fell short', () {
      expect(missed(view(credited: 3)), isTrue);
      expect(missed(view()), isFalse);
      expect(missed(view(credited: 3, free: true)), isFalse);
      expect(missed(view(credited: 3, sick: true)), isFalse);
      expect(missed(view(kind: DayKind.today, credited: 3)), isFalse);
    });
  });

  group('DayDetails', () {
    Future<void> pumpDetails(WidgetTester tester, DayView v) async {
      await pumpTab(tester, DayDetails(view: v));
      expectNoWords(tester);
    }

    testWidgets('before the first quota day: the date and a block', (
      tester,
    ) async {
      await pumpDetails(tester, view(beforeQuotas: true));
      expect(find.text('15.10'), findsOneWidget);
      expect(iconLabeled('no page quota yet'), findsOneWidget);
    });

    testWidgets('before the switch: the credited pages under history', (
      tester,
    ) async {
      await pumpDetails(tester, view(oldRule: true));
      expect(find.text('22'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsWidgets);
    });

    testWidgets('a past day, behind, with carried debt', (tester) async {
      await pumpDetails(tester, view(debt: 30));
      expect(find.text('22 / 17'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(iconLabeled('carried debt'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down), findsOneWidget);
    });

    testWidgets('today on pace, with carried credit', (tester) async {
      await pumpDetails(
        tester,
        view(kind: DayKind.today, line: 50, credit: 20),
      );
      expect(find.byIcon(Icons.today), findsOneWidget);
      expect(iconLabeled('on pace'), findsOneWidget);
      expect(iconLabeled('carried credit'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('a future day shows the assumption, or the simulation', (
      tester,
    ) async {
      await pumpDetails(tester, view(kind: DayKind.future, assumed: 17));
      expect(iconLabeled('assumed read'), findsOneWidget);
      expect(find.byIcon(Icons.science), findsNothing);
      await pumpDetails(
        tester,
        view(kind: DayKind.future, assumed: 57, simulated: 40),
      );
      expect(find.text('57 (+40)'), findsOneWidget);
      await pumpDetails(tester, view(assumed: 0, simulated: -17));
      expect(find.text('0 (-17)'), findsOneWidget);
    });

    testWidgets('a sick or free day asks nothing', (tester) async {
      await pumpDetails(tester, view(sick: true, required: 0));
      expect(iconLabeled('sick'), findsOneWidget);
      expect(iconLabeled('requirement'), findsNothing);
      await pumpDetails(tester, view(free: true));
      expect(iconLabeled('free'), findsOneWidget);
      expect(iconLabeled('requirement'), findsNothing);
    });
  });

  group('WeekdayDots', () {
    testWidgets('seven dots, the weekend larger', (tester) async {
      await pumpTab(tester, const WeekdayDots());
      final dots = tester.widgetList<WeekdayDot>(find.byType(WeekdayDot));
      expect(
        [for (final d in dots) d.weekend],
        [
          false, false, false, false, false, true, true, //
        ],
      );
      final sizes = [
        for (final e in find.byType(WeekdayDot).evaluate())
          tester
              .getSize(
                find.descendant(
                  of: find.byWidget(e.widget),
                  matching: find.byType(Container),
                ),
              )
              .width,
      ];
      expect(sizes.take(5).every((w) => w == 5), isTrue);
      expect(sizes.skip(5).every((w) => w == 10), isTrue);
    });
  });
}
