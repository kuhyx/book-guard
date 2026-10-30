import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/screens/reading_settings.dart';
import 'package:book_guard_app/src/screens/reading_style.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: ReadingSettingsScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();
  }

  double previewSize(WidgetTester tester) => tester
      .widget<Text>(find.byKey(ReadingSettingsScreen.previewKey))
      .style!
      .fontSize!;

  testWidgets('shows the size the reader will use', (tester) async {
    await pump(tester);
    expect(find.text('Text size: 18'), findsOneWidget);
    expect(previewSize(tester), 18);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, ReadingStyle.minFont);
    expect(slider.max, ReadingStyle.maxFont);
    expect(slider.divisions, 18);
  });

  testWidgets('a kept size outside the range is shown clamped', (tester) async {
    await api.saveFontSize(40);
    await pump(tester);
    expect(find.text('Text size: 32'), findsOneWidget);
  });

  testWidgets('dragging the slider previews and keeps the size', (
    tester,
  ) async {
    await pump(tester);
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(previewSize(tester), ReadingStyle.maxFont);
    expect(await api.savedFontSize(), ReadingStyle.maxFont);
    final preview = tester.widget<Text>(
      find.byKey(ReadingSettingsScreen.previewKey),
    );
    expect(preview.style!.color, ReadingStyle.ink);
  });
}
