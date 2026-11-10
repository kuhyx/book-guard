import 'package:book_guard_app/src/screens/picker_parts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<int> seen;

  setUp(() => seen = []);

  Future<void> pump(WidgetTester tester, {int value = 0, int count = 24}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NumberWheel(
                count: count,
                value: value,
                onChanged: seen.add,
              ),
            ),
          ),
        ),
      );

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(find.byWidgetPredicate((w) => w is Scrollable))
      .position;

  Offset centre(WidgetTester tester) =>
      tester.getCenter(find.byType(NumberWheel));

  testWidgets('one mouse-wheel notch is one snapped step, both ways', (
    tester,
  ) async {
    await pump(tester, value: 5);
    final mouse = TestPointer(1, PointerDeviceKind.mouse)
      ..hover(centre(tester));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    expect(seen.last, 6);
    expect(position(tester).pixels % NumberWheel.itemExtent, 0);
    // Two quick notches add up.
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -30)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -30)));
    await tester.pumpAndSettle();
    expect(seen.last, 4, reason: '$seen');
    await tester.sendEventToBinding(mouse.scroll(const Offset(30, 0)));
    await tester.pumpAndSettle();
    expect(seen.last, 4, reason: 'a sideways scroll is not a step');
    await tester.sendEventToBinding(
      PointerScaleEvent(position: centre(tester), scale: 2),
    );
    await tester.pumpAndSettle();
    expect(seen.last, 4, reason: 'a pinch is not a step');
  });

  testWidgets('the wheel loops past the end and before the start', (
    tester,
  ) async {
    await pump(tester, value: 23);
    final mouse = TestPointer(1, PointerDeviceKind.mouse)
      ..hover(centre(tester));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 50)));
    await tester.pumpAndSettle();
    expect(seen.last, 0);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -50)));
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -50)));
    await tester.pumpAndSettle();
    expect(seen.last, 22);
  });

  testWidgets('tapping a neighbour selects it; the centre stays put', (
    tester,
  ) async {
    await pump(tester, count: 60);
    await tester.tapAt(
      centre(tester) + const Offset(0, NumberWheel.itemExtent),
    );
    await tester.pumpAndSettle();
    expect(seen.last, 1);
    await tester.tapAt(
      centre(tester) - const Offset(0, NumberWheel.itemExtent),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      centre(tester) - const Offset(0, NumberWheel.itemExtent),
    );
    await tester.pumpAndSettle();
    expect(seen.last, 59, reason: 'the short way round, not a lap');
    seen.clear();
    await tester.tapAt(centre(tester));
    await tester.pumpAndSettle();
    expect(seen, isEmpty);
  });

  testWidgets('a mouse drag and a touch drag both turn it', (tester) async {
    await pump(tester, value: 10, count: 60);
    await tester.dragFrom(
      centre(tester),
      const Offset(0, -NumberWheel.itemExtent * 2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(seen.last, greaterThanOrEqualTo(12));
    final afterMouse = seen.last;
    await tester.drag(
      find.byType(NumberWheel),
      const Offset(0, NumberWheel.itemExtent * 3),
    );
    await tester.pumpAndSettle();
    expect(seen.last, lessThan(afterMouse));
  });

  test('pad2 pads to two digits', () {
    expect(pad2(7), '07');
    expect(pad2(23), '23');
  });
}
