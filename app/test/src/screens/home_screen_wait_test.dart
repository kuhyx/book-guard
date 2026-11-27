import 'dart:async';

import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/finders_a.dart';
import '../../support/finders_read.dart';
import '../../support/states.dart';

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi(state: sampleState()));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: HomeScreen(
          api: api,
          desktop: false,
          refreshEvery: const Duration(seconds: 1),
        ),
      ),
    );
    await settle(tester);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('a sent summary frees the Read tab before the PC answers', (
    tester,
  ) async {
    // kuhy, 2026-11-24: never wait on the PC. The summary is out with the
    // grader; the next start is offered while the fetch still hangs.
    api.state = sampleState({
      'open_start': null,
      'sessions': [
        {'id': 'session:c-d', 'status': 'needs-quiz', 'start_page': '21'},
      ],
    });
    await pump(tester);
    await tester.tap(navTab(Icons.menu_book));
    await settle(tester);
    expect(spoken('Submit summary'), findsOneWidget);
    final pc = Completer<void>();
    api.fetchGate = pc.future;
    await api.markGrading('session:c-d');
    await tester.tap(iconLabeled('refresh'));
    await settle(tester);
    expect(spoken('Submit summary'), findsNothing);
    expect(spoken('Start reading'), findsOneWidget);
    pc.complete();
    await settle(tester);
  });
}
