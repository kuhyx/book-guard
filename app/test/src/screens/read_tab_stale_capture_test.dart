import 'package:book_guard_app/src/capture.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/fake_reader.dart';
import '../../support/finders_read.dart';
import '../../support/states.dart';

final _now = DateTime(2026, 11, 22, 11, 31);

Capture _start(DateTime at) =>
    Capture(id: 'a1', label: 'start', fileName: 'IMG.jpg', takenAt: at);

void main() {
  Future<void> pump(WidgetTester tester, List<Capture> captures) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTab(
      tester,
      ReadTab(
        api: FakeApi(),
        state: readingState(),
        desktop: false,
        onChanged: () async {},
        reader: FakeReader(
          fakeScan([(473, (left: 17, top: 54, right: 23, bottom: 58))]),
        ),
        captures: captures,
        clock: () => _now,
      ),
    );
  }

  testWidgets('a 26-day-old stored start photo leaves the camera button', (
    tester,
  ) async {
    // 2026-11-22 11:31: the p. 473 start photo of 2026-10-27 20:15 stood in
    // for the camera; tapping it re-sent that photo, never the camera.
    await pump(tester, [_start(DateTime(2026, 10, 27, 20, 15))]);
    expect(spoken('Start reading'), findsOneWidget);
    expect(find.byIcon(Icons.restore), findsNothing);
  });

  testWidgets('a fresh stored photo sits beside the camera button', (
    tester,
  ) async {
    await pump(tester, [_start(_now.subtract(const Duration(hours: 2)))]);
    expect(spoken('Start reading'), findsOneWidget);
    expect(find.byIcon(Icons.restore), findsOneWidget);
  });
}
