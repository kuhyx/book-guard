import 'package:book_guard_app/src/screens/type_page_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/finders_read.dart';

// The page-number dialog types on its own keypad, never the system keyboard
// (a phone's keyboard once refused a digit after a deleted pre-fill).

void main() {
  /// What the dialog popped (null: cancelled or still open).
  int? popped;

  Future<void> open(WidgetTester tester, {int? initial}) async {
    popped = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => popped = await showDialog<int>(
                context: context,
                builder: (_) => TypePageDialog(initial: initial),
              ),
              child: const Icon(Icons.dialpad),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
  }

  String field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  Future<void> key(WidgetTester tester, String k) async {
    await tester.tap(find.byKey(ValueKey('keypad-$k')));
    await tester.pump();
  }

  testWidgets('234 pre-filled: delete the 4, type 7, send 237', (tester) async {
    await open(tester, initial: 234);
    expect(field(tester), '234');
    await key(tester, 'back');
    expect(field(tester), '23');
    await key(tester, '7');
    expect(field(tester), '237');
    await tester.tap(spoken('Send the typed page number'));
    await tester.pumpAndSettle();
    expect(find.byType(TypePageDialog), findsNothing);
    expect(popped, 237);
  });

  testWidgets('the pre-fill can be cleared to any number', (tester) async {
    await open(tester, initial: 234);
    for (var i = 0; i < 4; i++) {
      await key(tester, 'back');
    }
    expect(field(tester), '');
    for (final d in ['1', '0', '0', '2', '3', '4', '5', '6', '8', '9']) {
      await key(tester, d);
    }
    // Five digits at most: no book has 100 000 pages.
    expect(field(tester), '10023');
  });

  testWidgets('the system keyboard is never asked for', (tester) async {
    await open(tester);
    final f = tester.widget<TextField>(find.byType(TextField));
    expect(f.keyboardType, TextInputType.none);
  });
}
