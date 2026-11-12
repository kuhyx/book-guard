import 'package:book_guard_app/src/pace/day_views.dart';
import 'package:book_guard_app/src/screens/icon_num.dart';
import 'package:book_guard_app/src/screens/pace_cells.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/day_view_fixture.dart';
import '../../support/fake_api.dart';
import '../../support/no_words.dart';

void main() {
  group('DayCell', () {
    Future<int> pumpCell(
      WidgetTester tester,
      DayView v, {
      bool selected = false,
      bool showDot = false,
    }) async {
      var taps = 0;
      await pumpTab(
        tester,
        Row(
          children: [
            Expanded(
              child: DayCell(
                view: v,
                selected: selected,
                showDot: showDot,
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

    testWidgets('a met day is green with a check, taps select it', (
      tester,
    ) async {
      expect(await pumpCell(tester, view()), 1);
      expect(find.text('22/17'), findsOneWidget);
      expect(decoration(tester).color, isNotNull);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expectNoWords(tester);
    });

    testWidgets('a missed past day is red with a cross, selected is outlined', (
      tester,
    ) async {
      await pumpCell(tester, view(credited: 3), selected: true);
      final box = decoration(tester);
      expect(box.color, isNotNull);
      expect((box.border! as Border).top.width, 2);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('today, free, future and simulated days are not filled', (
      tester,
    ) async {
      await pumpCell(tester, view(kind: DayKind.today, credited: 1));
      expect(decoration(tester).color, isNull);
      await pumpCell(tester, view(free: true, credited: 3));
      expect(decoration(tester).color, isNull);
      expect(find.byIcon(freeGlyph), findsOneWidget);
      await pumpCell(tester, view(kind: DayKind.future, simulated: 5));
      expect(decoration(tester).color, isNull);
      final text = tester.widget<Text>(find.text('22/17'));
      expect(text.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('the week row puts a weekday dot over the date', (
      tester,
    ) async {
      await pumpCell(tester, view(), showDot: true);
      expect(find.byType(WeekdayDot), findsOneWidget);
      expect(
        tester.widget<WeekdayDot>(find.byType(WeekdayDot)).weekend,
        isFalse,
      );
    });
  });
}
