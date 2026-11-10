import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/grader_note.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_read.dart';

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
    await tester.tap(spoken('Submit summary'));
    await tester.pump();
    expect(field(tester).enabled, isFalse);
    expect(busyBar(), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // leave the tab
    await pump(tester);
    // Back later: the hourglass chip with the time it went out.
    expect(cueWith(Icons.hourglass_top), findsOneWidget);
    expect(field(tester).enabled, isFalse);
    expect(field(tester).controller?.text, 'x' * 160);
    answer.complete(const GuardResponse(ok: true, code: 'passed'));
    await settle(tester);
  });

  testWidgets('the length bar fills to 150 characters and ticks', (
    tester,
  ) async {
    await pump(tester);
    double? fill() => tester
        .widget<LinearProgressIndicator>(
          find.byWidgetPredicate(
            (w) => w is LinearProgressIndicator && w.value != null,
          ),
        )
        .value;
    expect(fill(), 0);
    expect(spoken('long enough'), findsNothing);
    await tester.enterText(find.byType(TextField), 'x' * 75);
    await tester.pump();
    expect(fill(), 0.5);
    await tester.enterText(find.byType(TextField), 'x' * 150);
    await tester.pump();
    expect(fill(), 1);
    expect(spoken('long enough'), findsOneWidget);
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
    expect(find.byType(GraderNoteChip), findsOneWidget);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(find.byType(GraderNoteChip), findsNothing);
  });

  testWidgets('a failure that arrives later unlocks the box', (tester) async {
    // Offline: the request is queued, no verdict yet.
    api.onSend = (_) async => const GuardResponse(ok: true, code: 'queued');
    Widget panel(SessionInfo session) => SingleChildScrollView(
      child: SummaryPanel(api: api, session: session, onChanged: () async {}),
    );
    await pumpTab(tester, panel(_session));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'x' * 160);
    await tester.tap(spoken('Submit summary'));
    await settle(tester);
    expect(field(tester).enabled, isFalse, reason: 'with the grader');
    // The PC fails it later: the home screen settles the marker and
    // rebuilds the panel with the session's retry.
    final failed = SessionInfo.fromJson({
      'id': 'session:a-b',
      'start_page': 51,
      'end_page': 104,
      'status': 'needs-quiz',
      'retry': {
        'summary': 'x' * 160,
        'missing': ['the letter'],
        'graded_at': DateTime.now()
            .add(const Duration(minutes: 1))
            .toUtc()
            .toIso8601String(),
      },
    });
    await api.settleGrading(failed);
    await pumpTab(tester, panel(failed));
    await settle(tester);
    expect(field(tester).enabled, isTrue, reason: 'the rewrite can start');
    expect(find.text('“the letter”'), findsOneWidget, reason: 'its topic');
  });
}
