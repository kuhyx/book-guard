import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/finders_read.dart';

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

  Future<void> pump(
    WidgetTester tester,
    SessionInfo session, {
    Pace? pace,
  }) async {
    await pumpTab(
      tester,
      SingleChildScrollView(
        child: SummaryPanel(
          api: api,
          session: session,
          onChanged: () async {},
          pace: pace,
        ),
      ),
    );
    await settle(tester);
  }

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  /// Sends a summary; kuhy, 2026-11-24: it is queued, never waited on.
  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'x' * 160);
    await tester.tap(spoken('Submit summary'));
    await settle(tester);
  }

  /// The PC's fail arrives with the next snapshot: a retry newer than the
  /// marker; the home screen settles the marker, then redraws the panel.
  Future<void> failLater(WidgetTester tester, int round) async {
    final later = SessionInfo.fromJson({
      'id': _id,
      'start_page': 51,
      'end_page': 104,
      'status': 'needs-quiz',
      'retry': {
        'feedback': 'Name two events.',
        'summary': 'x' * 160,
        'missing': ['two events'],
        'graded_at': DateTime.now()
            .add(Duration(minutes: round))
            .toIso8601String(),
      },
    });
    await api.settleGrading(later);
    await pump(tester, later);
  }

  testWidgets('a sent summary is out with the grader, nothing waited on', (
    tester,
  ) async {
    var asked = false;
    api.onSend = (_) async {
      asked = true;
      return const GuardResponse(ok: true, code: 'failed', passed: false);
    };
    await pump(tester, _session());
    await submit(tester);
    expect(asked, isFalse);
    expect(await api.gradingSince(_id), isNotNull);
    expect(await api.loadDraft(_id), 'x' * 160);
  });

  testWidgets('each later fail unlocks the box, keeps the text, names topics', (
    tester,
  ) async {
    await pump(tester, _session(retry: true));
    for (final round in [1, 2]) {
      // There is no limit on rewrites.
      await submit(tester);
      await failLater(tester, round);
      expect(find.text('“two events”'), findsOneWidget);
      expect(field(tester).enabled, isTrue);
      expect(field(tester).controller?.text, 'x' * 160);
      expect(await api.loadDraft(_id), 'x' * 160);
      expect(await api.gradingSince(_id), isNull);
    }
  });

  testWidgets('the rewrite shows topics, never the prose, from the old text', (
    tester,
  ) async {
    await pump(tester, _session(retry: true));
    // The grader's prose is not painted; the missing topics are, quoted,
    // under a red cross with their count and the retry arrow.
    expect(find.text('Name two events.'), findsNothing);
    expect(cueOf(CueKind.error), findsOneWidget);
    expect(
      find.descendant(of: cueOf(CueKind.error), matching: find.text('2')),
      findsOneWidget,
    );
    expect(find.text('“what he did in the village”'), findsOneWidget);
    expect(find.text('“who he worked for”'), findsOneWidget);
    expect(spoken('rewrite'), findsOneWidget);
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

  testWidgets('the gaming bonus is a bolt on the button, known offline', (
    tester,
  ) async {
    final big = SessionInfo.fromJson(const {
      'id': 's',
      'start_page': 1,
      'end_page': 54,
      'pages': 53,
      'minutes': 49,
      'status': 'needs-quiz',
    });
    Pace pace({int required = 60, int today = 10, bool bonus = false}) =>
        Pace.fromJson({
          'today_required': required,
          'pages_today': today,
          'bonus_today': bonus,
        });
    await pump(tester, big, pace: pace());
    expect(spoken('gaming bonus'), findsOneWidget);
    // 10 + 53 short of 64; a bonus already earned today; no pace known; a
    // PC too old to send today's requirement.
    final old = Pace.fromJson(const {'pages_today': 10});
    for (final short in [pace(required: 64), pace(bonus: true), null, old]) {
      await tester.pumpWidget(const SizedBox());
      await pump(tester, big, pace: short);
      expect(spoken('gaming bonus'), findsNothing);
    }
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
    expect(find.textContaining('“'), findsNothing);
    expect(cueOf(CueKind.error), findsOneWidget);
  });
}
