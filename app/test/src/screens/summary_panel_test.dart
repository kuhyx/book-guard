import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

final _session = SessionInfo.fromJson(const {
  'id': 'session:a-b',
  'start_page': 51,
  'end_page': 104,
  'status': 'needs-quiz',
});

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> pump(WidgetTester tester, {GuardState? state}) async {
    await pumpTab(
      tester,
      SingleChildScrollView(
        child: SummaryPanel(
          api: api,
          session: _session,
          onChanged: () async {},
          state: state,
        ),
      ),
    );
    await settle(tester);
  }

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  testWidgets('typed text survives leaving the tab', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'Xi in Shaanxi');
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    expect(field(tester).controller?.text, 'Xi in Shaanxi');
  });

  testWidgets('while the grader has it the text is locked; back later, it '
      'says so', (tester) async {
    final answer = Completer<GuardResponse>();
    api.onSend = (_) => answer.future;
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'x' * 160);
    await tester.tap(find.text('Submit summary'));
    await tester.pump();
    expect(field(tester).enabled, isFalse);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // leave the tab
    await pump(tester);
    expect(find.textContaining('Sent to the grader at'), findsOneWidget);
    expect(field(tester).enabled, isFalse);
    expect(field(tester).controller?.text, 'x' * 160);
    answer.complete(const GuardResponse(ok: true, message: 'late'));
    await settle(tester);
  });

  testWidgets('a graded summary forgets its draft and marker', (tester) async {
    await api.saveDraft(_session.id, 'old');
    await api.markGrading(_session.id);
    await api.doneGrading(_session.id);
    expect(await api.loadDraft(_session.id), '');
    expect(await api.gradingSince(_session.id), isNull);
  });

  testWidgets('the outage note goes when the reset time comes', (tester) async {
    final until = DateTime.now().add(const Duration(minutes: 1));
    final state = GuardState.fromJson({
      'claude_down_since': DateTime.now().toIso8601String(),
      'claude_down_until': until.toIso8601String(),
    });
    await api.markGrading(_session.id);
    await pump(tester, state: state);
    expect(find.textContaining('local model'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(find.textContaining('local model'), findsNothing);
  });
}
