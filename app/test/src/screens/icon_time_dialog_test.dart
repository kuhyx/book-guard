import 'package:book_guard_app/src/screens/icon_pickers.dart';
import 'package:book_guard_app/src/screens/icon_time_dialog.dart';
import 'package:book_guard_app/src/screens/picker_parts.dart';
import 'package:book_guard_app/src/screens/session_times.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Range = ({TimeOfDay start, TimeOfDay end});

void main() {
  late List<_Range?> results;

  setUp(() => results = []);

  Future<void> open(WidgetTester tester, TimeOfDay start, TimeOfDay end) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showIconTimeRangePicker(
                  context: context,
                  initialStart: start,
                  initialEnd: end,
                ),
              ),
              child: const SizedBox(width: 10, height: 10),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
  }

  Future<void> notch(WidgetTester tester, int wheel, double dy) async {
    final at = tester.getCenter(find.byType(NumberWheel).at(wheel));
    final mouse = TestPointer(1, PointerDeviceKind.mouse)..hover(at);
    await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
    await tester.pumpAndSettle();
  }

  testWidgets('wheels wrap with no carry; +1 follows the end live', (
    tester,
  ) async {
    await open(
      tester,
      const TimeOfDay(hour: 23, minute: 59),
      const TimeOfDay(hour: 23, minute: 59),
    );
    final start = tester.getCenter(find.byIcon(Icons.play_arrow)).dy;
    expect(start, lessThan(tester.getCenter(find.byIcon(Icons.stop)).dy));
    expect(find.text('+1'), findsNothing);
    await notch(tester, 1, 40); // start minute 59 -> 00, hour stays 23
    expect(find.text('+1'), findsNothing, reason: 'end 23:59 after 23:00');
    await notch(tester, 3, 40); // end minute -> 00: 23:00 vs start 23:00
    expect(find.text('+1'), findsNothing);
    await notch(tester, 2, 40); // end hour 23 -> 00
    expect(find.text('+1'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(results.single?.start, const TimeOfDay(hour: 23, minute: 0));
    expect(results.single?.end, const TimeOfDay(hour: 0, minute: 0));
  });

  testWidgets('the close icon returns nothing', (tester) async {
    const t = TimeOfDay(hour: 8, minute: 5);
    await open(tester, t, t);
    expect(find.text('08'), findsWidgets);
    expect(find.text('05'), findsWidgets);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(results.single, isNull);
  });

  test('the +1 badge rule is exactly onDayOf rolling the end over', () {
    for (var s = 0; s < 24 * 60; s += 7) {
      final startAt = DateTime(2026, 10, 3, s ~/ 60, s % 60);
      final start = TimeOfDay(hour: s ~/ 60, minute: s % 60);
      for (var e = 0; e < 24 * 60; e++) {
        final end = TimeOfDay(hour: e ~/ 60, minute: e % 60);
        final rolled = onDayOf(startAt, end).day != startAt.day;
        expect(endRollsOver(start, end), rolled, reason: '$start $end');
      }
    }
  });
}
