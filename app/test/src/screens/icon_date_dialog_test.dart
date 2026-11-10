import 'package:book_guard_app/src/screens/icon_date_dialog.dart';
import 'package:book_guard_app/src/screens/icon_pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/no_words.dart';

void main() {
  late List<DateTime?> results;

  setUp(() => results = []);

  /// Opens the picker from a button, the way the screens do.
  Future<void> open(
    WidgetTester tester, {
    required DateTime initial,
    required DateTime first,
    required DateTime last,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showIconDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: first,
                  lastDate: last,
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

  PickerDay day(WidgetTester tester, int d) => tester.widget(
    find.byWidgetPredicate((w) => w is PickerDay && w.day == d),
  );

  VoidCallback? chevron(WidgetTester tester, IconData icon) => tester
      .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
      .onPressed;

  Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await tester.pumpAndSettle();
  }

  testWidgets('numerals and chevrons step the month inside the range', (
    tester,
  ) async {
    await open(
      tester,
      initial: DateTime.utc(2026, 11, 10),
      first: DateTime.utc(2026, 10, 12),
      last: DateTime.utc(2026, 12, 3),
    );
    expect(find.text('2026 · 11'), findsOneWidget);
    expectNoWords(
      tester,
      find.byType(IconDateDialog),
      spoken: [
        Icons.check,
        Icons.close,
        Icons.chevron_left,
        Icons.chevron_right,
      ],
    );
    await tapIcon(tester, Icons.chevron_left);
    expect(find.text('2026 · 10'), findsOneWidget);
    expect(chevron(tester, Icons.chevron_left), isNull);
    expect(day(tester, 11).enabled, isFalse);
    expect(day(tester, 12).enabled, isTrue);
    await tester.tap(find.text('11'));
    await tester.pump();
    expect(day(tester, 11).selected, isFalse, reason: 'dimmed: not tappable');
    await tapIcon(tester, Icons.chevron_right);
    await tapIcon(tester, Icons.chevron_right);
    expect(find.text('2026 · 12'), findsOneWidget);
    expect(chevron(tester, Icons.chevron_right), isNull);
    expect(day(tester, 3).enabled, isTrue);
    expect(day(tester, 4).enabled, isFalse);
    await tester.tap(find.text('2'));
    await tapIcon(tester, Icons.check);
    expect(results.single, DateTime(2026, 12, 2));
    expect(results.single!.isUtc, isFalse, reason: 'local, as Material');
  });

  testWidgets('Monday first, Sat/Sun columns tinted, the year rolls', (
    tester,
  ) async {
    await open(
      tester,
      initial: DateTime(2026, 12, 31, 18),
      first: DateTime(2026),
      last: DateTime(2027, 12, 31),
    );
    expect(day(tester, 31).selected, isTrue);
    await tapIcon(tester, Icons.chevron_right);
    expect(find.text('2027 · 01'), findsOneWidget);
    // Fri 1 January 2027 is in the fifth column, Mon 4 in the first.
    double x(int d) => tester.getCenter(find.text('$d')).dx;
    expect(x(4), lessThan(x(1)));
    expect(x(1), lessThan(x(2)));
    expect(x(2), lessThan(x(3)));
    Color? cellColour(int d) => tester
        .widget<Container>(
          find
              .ancestor(of: find.text('$d'), matching: find.byType(Container))
              .at(1),
        )
        .color;
    expect(cellColour(1), isNull);
    expect(cellColour(2), isNotNull, reason: 'Saturday tinted');
    expect(cellColour(3), isNotNull, reason: 'Sunday tinted');
    expect(cellColour(4), isNull);
    expect(day(tester, 31).selected, isFalse, reason: 'other month');
    await tapIcon(tester, Icons.close);
    expect(results.single, isNull);
  });
}
