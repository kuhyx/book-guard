import 'package:book_guard_app/src/next_step.dart';
import 'package:book_guard_app/src/screens/home_nav_bar.dart';
import 'package:book_guard_app/src/screens/session_buttons.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/states.dart';
import '../../support/status_pump.dart';

// kuhy, 2026-11-24: start, stop and the summary looked alike. Each step
// has its own big glyph and colour; the camera is only a small badge.
Future<FilledButton> _button(WidgetTester tester, StepKind kind) async {
  await pumpTab(
    tester,
    SessionButtons(
      step: NextStep(kind),
      busy: false,
      reading: kind == StepKind.stop ? 40 : null,
      desktop: false,
      onPhoto: (_) {},
      onResume: (_) {},
    ),
  );
  return tester.widget<FilledButton>(find.byType(FilledButton));
}

Color? _fill(WidgetTester tester, FilledButton button) =>
    button.style?.backgroundColor?.resolve(const {});

const _reading =
    'Reading since p. 111 (Fri 12:34) -- photograph the page where you stop';

void main() {
  testWidgets('start is a green play, the camera a small badge', (
    tester,
  ) async {
    final button = await _button(tester, StepKind.start);
    final colors = tester.element(find.byType(FilledButton)).statusColors;
    expect(_fill(tester, button), colors.success);
    expect(tester.getSize(find.byIcon(Icons.play_arrow)).width, 32);
    expect(tester.getSize(find.byIcon(Icons.photo_camera)).width, 16);
  });

  testWidgets('stop is a red stop with the start page', (tester) async {
    final button = await _button(tester, StepKind.stop);
    final colors = tester.element(find.byType(FilledButton)).statusColors;
    expect(_fill(tester, button), colors.danger);
    expect(tester.getSize(find.byIcon(Icons.stop)).width, 32);
    expect(find.text('40'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  for (final (kind, glyph, name) in [
    (StepKind.summary, Icons.edit, 'warning'),
    (StepKind.stop, Icons.stop, 'danger'),
  ]) {
    testWidgets('the Read tab badge is the $kind step glyph', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            bottomNavigationBar: HomeNavBar(
              selected: 0,
              onSelected: (_) {},
              readStep: kind,
            ),
          ),
        ),
      );
      final badge = tester.widget<Badge>(find.byType(Badge));
      final colors = tester.element(find.byType(Badge)).statusColors;
      expect(
        badge.backgroundColor,
        name == 'danger' ? colors.danger : colors.warning,
      );
      expect(
        find.descendant(of: find.byType(Badge), matching: find.byIcon(glyph)),
        findsOneWidget,
      );
    });
  }

  testWidgets('no step owed on the Read tab: no badge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: HomeNavBar(selected: 0, onSelected: (_) {}),
        ),
      ),
    );
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('the Status tile while reading is the red stop', (tester) async {
    await pumpStatus(
      tester,
      state: sampleState({
        'todo': const [_reading],
      }),
    );
    final stop = tester.widget<Icon>(find.byIcon(Icons.stop));
    final colors = tester.element(find.byIcon(Icons.stop)).statusColors;
    expect(stop.color, colors.danger);
    expect(find.byIcon(Icons.auto_stories), findsNothing);
  });
}
