import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

const _id = 'session:a-b';
final _graded = DateTime.utc(2020); // before any marker made "now"

SessionInfo _session({bool retry = false, String status = 'needs-quiz'}) =>
    SessionInfo.fromJson({
      'id': _id,
      'start_page': 51,
      'end_page': 104,
      'status': status,
      'retry': retry
          ? {
              'feedback': 'Name two events.',
              'summary': 'Xi in the village',
              'missing': ['what he did in the village', 'who he worked for'],
              'graded_at': _graded.toIso8601String(),
            }
          : null,
    });

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> pump(WidgetTester tester, SessionInfo session) async {
    await pumpTab(
      tester,
      SingleChildScrollView(
        child: SummaryPanel(api: api, session: session, onChanged: () async {}),
      ),
    );
    await settle(tester);
  }

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  Future<void> submitFailing(WidgetTester tester) async {
    api.onSend = (_) async => const GuardResponse(
      ok: true,
      message: 'Too thin. Rewrite the summary and send it again.',
      passed: false,
    );
    await tester.enterText(find.byType(TextField), 'x' * 160);
    await tester.tap(find.text('Submit summary'));
    await settle(tester);
  }

  testWidgets('a first failure unlocks the box and keeps the text', (
    tester,
  ) async {
    await pump(tester, _session());
    await submitFailing(tester);
    expect(find.textContaining('Rewrite the summary'), findsOneWidget);
    expect(field(tester).enabled, isTrue);
    expect(field(tester).controller?.text, 'x' * 160);
    expect(await api.loadDraft(_id), 'x' * 160);
    expect(await api.gradingSince(_id), isNull);
    // The credit is still owed after a fail: the rewrite earns the same.
    expect(find.textContaining('Passing credits'), findsOneWidget);
  });

  testWidgets('a rewrite failing again unlocks the box once more', (
    tester,
  ) async {
    await pump(tester, _session(retry: true));
    await submitFailing(tester);
    expect(field(tester).enabled, isTrue);
    expect(field(tester).controller?.text, 'x' * 160);
    expect(await api.loadDraft(_id), 'x' * 160);
    expect(await api.gradingSince(_id), isNull);
    expect(find.textContaining('Passing credits'), findsOneWidget);
    // And again: there is no limit.
    await tester.tap(find.text('Submit summary'));
    await settle(tester);
    expect(field(tester).enabled, isTrue);
    expect(await api.loadDraft(_id), 'x' * 160);
  });

  testWidgets('a passing rewrite is final: draft forgotten, no credit hint', (
    tester,
  ) async {
    await pump(tester, _session(retry: true));
    api.onSend = (_) async =>
        const GuardResponse(ok: true, message: 'Well read.', passed: true);
    await tester.enterText(find.byType(TextField), 'x' * 160);
    await tester.tap(find.text('Submit summary'));
    await settle(tester);
    expect(await api.loadDraft(_id), '');
    expect(await api.gradingSince(_id), isNull);
    expect(find.textContaining('Passing credits'), findsNothing);
  });

  testWidgets('the rewrite shows the feedback and starts from the old text', (
    tester,
  ) async {
    await pump(tester, _session(retry: true));
    expect(find.text('Name two events.'), findsOneWidget);
    expect(find.textContaining('no limit on rewrites'), findsOneWidget);
    expect(
      find.text(
        'To be accepted, add:\n- what he did in the village\n'
        '- who he worked for',
      ),
      findsOneWidget,
    );
    expect(field(tester).controller?.text, 'Xi in the village');
    expect(field(tester).enabled, isTrue);
  });

  testWidgets('a kept draft wins over the old text', (tester) async {
    await api.saveDraft(_id, 'my rewrite');
    await pump(tester, _session(retry: true));
    expect(field(tester).controller?.text, 'my rewrite');
  });

  test(
    'settling: a stale marker unlocks, an in-flight rewrite stays',
    () async {
      await api.saveDraft(_id, 'text');
      await api.store.write(
        'grading/$_id',
        // Sent before the failure was graded: stale.
        Uint8List.fromList(
          utf8.encode(
            _graded.subtract(const Duration(minutes: 1)).toIso8601String(),
          ),
        ),
      );
      await api.settleGrading(_session(retry: true));
      expect(await api.gradingSince(_id), isNull);
      expect(await api.loadDraft(_id), 'text');

      await api.markGrading(_id); // now: the rewrite itself
      await api.settleGrading(_session(retry: true));
      expect(await api.gradingSince(_id), isNotNull);
      await api.settleGrading(_session()); // no retry: nothing to settle
      expect(await api.gradingSince(_id), isNotNull);

      await api.settleGrading(_session(status: 'failed-quiz'));
      expect(await api.gradingSince(_id), isNull);
      expect(await api.loadDraft(_id), '');
    },
  );

  test('a failed summary awaiting its rewrite is graded and says so', () {
    expect(statusText(_session(retry: true)), 'summary failed: rewrite it');
    expect(statusText(_session()), 'write the summary');
    expect(_session(retry: true).graded, isTrue);
    expect(_session().graded, isFalse);
    expect(_session(status: 'credited').graded, isTrue);
    expect(_session(status: 'failed-quiz').graded, isTrue);
    expect(statusText(_session(status: 'odd')), 'odd');
  });

  test('the credit is known offline, bonus and outage rule included', () {
    final big = SessionInfo.fromJson(const {
      'id': 's',
      'pages': 53,
      'minutes': 49,
      'status': 'needs-quiz',
    });
    expect(
      expectedCredit(big),
      'Passing credits 53 pages and +1h gaming. If the grader is unreachable '
      'for an hour, it is credited without grading.',
    );
    expect(expectedCredit(_session()), startsWith('Passing credits 0 pages. '));
  });

  testWidgets('a retry without a missing list shows no empty list', (
    tester,
  ) async {
    final bare = SessionInfo.fromJson({
      'id': _id,
      'status': 'needs-quiz',
      'retry': {'feedback': 'Thin.', 'summary': 's'},
    });
    expect(bare.retry?.missing, isEmpty);
    await pump(tester, bare);
    expect(find.textContaining('To be accepted'), findsNothing);
    expect(find.textContaining('Passing credits'), findsOneWidget);
  });
}
