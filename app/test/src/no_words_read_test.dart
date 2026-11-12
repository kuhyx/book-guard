/// The zero-text guard over the Read tab and the summary panel.
library;

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/grader_note.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_api.dart';
import '../support/fake_reader.dart';
import '../support/finders_read.dart';
import '../support/no_words.dart';
import '../support/no_words_read_support.dart';
import '../support/states.dart';

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Widget tab({
    GuardState? state,
    List<JournalEntry> journal = const [],
    List<Capture> captures = const [],
    bool desktop = false,
  }) => ReadTab(
    api: api,
    state: state,
    desktop: desktop,
    onChanged: () async {},
    reader: desktop ? null : FakeReader(fakeScan([])),
    local: localView(state, journal),
    journal: journal,
    captures: captures,
    photoSource: ({required camera}) async =>
        XFile.fromData(readBytes, path: '/DCIM/IMG.jpg'),
  );

  group('the Read tab', () {
    testWidgets('empty: no state at all', (tester) async {
      await showTab(tester, tab(), scroll: false);
      expectNoWords(tester, content: readContent);
    });

    testWidgets('mid-session with a summary, a check page and photos', (
      tester,
    ) async {
      await showTab(
        tester,
        tab(state: withPhotos(filedPhotos())),
        scroll: false,
      );
      expectNoWords(tester, content: readContent);
    });

    testWidgets('desktop, waiting photos and a stored capture', (tester) async {
      final journal = [journalEntry('start_a.jpg', 'start', 51)];
      await showTab(
        tester,
        tab(
          state: readingState(openStart: 51),
          desktop: true,
          journal: journal,
          captures: [
            Capture(
              id: 'a1',
              label: 'check19',
              fileName: 'IMG.jpg',
              takenAt: DateTime(2026, 10, 23, 10, 6),
            ),
          ],
        ),
        scroll: false,
      );
      expectNoWords(tester, content: readContent);
    });

    testWidgets('with failed photos listed', (tester) async {
      await api.store.write('photos/stop_b.jpg', readBytes);
      await showTab(
        tester,
        tab(
          state: withPhotos([
            reading(
              name: 'start_a.jpg',
              kind: 'other',
              page: null,
              status: 'rejected',
              reason: 'no page number found',
            ),
          ]),
          journal: [
            journalEntry('start_a.jpg', 'start', 51),
            journalEntry('stop_b.jpg', 'stop', null),
          ],
        ),
        scroll: false,
      );
      // They live on the photos page; the switch carries a dot meanwhile.
      expect(find.byType(Badge), findsOneWidget);
      await tester.tap(spoken('photos'));
      await settle(tester, 10);
      expect(spoken('failed photos'), findsOneWidget);
      expectNoWords(tester, content: readContent);
    });

    testWidgets('an upload error is an icon snackbar', (tester) async {
      api.uploadError = shareDown();
      await showTab(
        tester,
        tab(state: sampleState(), desktop: true),
        scroll: false,
      );
      await tester.tap(spoken('Stop reading'));
      await settle(tester, 10);
      expect(inSnack(cueOf(CueKind.error)), findsOneWidget);
      expectNoWords(tester, content: readContent);
    });
  });

  group('the summary', () {
    SessionInfo session({Map<String, Object?>? retry}) => SessionInfo.fromJson({
      'id': 'session:a-b',
      'start_page': 51,
      'end_page': 104,
      'pages': 53,
      'status': 'needs-quiz',
      'retry': retry,
    });

    Widget panel(SessionInfo s, {GuardState? state, Pace? pace}) =>
        SummaryPanel(
          api: api,
          session: s,
          onChanged: () async {},
          state: state,
          pace: pace,
        );

    testWidgets('empty, then long enough', (tester) async {
      await showTab(tester, panel(session()));
      expectNoWords(tester, content: readContent);
      await tester.enterText(find.byType(TextField), 'x' * 160);
      await tester.pump();
      expect(spoken('long enough'), findsOneWidget);
      expectNoWords(tester, content: readContent);
    });

    testWidgets('a failure to rewrite lists the topics', (tester) async {
      await showTab(
        tester,
        panel(
          session(
            retry: {
              'feedback': 'Name two events.',
              'summary': 'Kaladin trains.',
              'missing': ['the habit loop', 'Kaladin'],
            },
          ),
        ),
      );
      expect(find.text('Name two events.'), findsNothing);
      expectNoWords(tester, content: readContent);
    });

    testWidgets('with the grader, an outage and the bonus bolt', (
      tester,
    ) async {
      await api.markGrading('session:a-b');
      final state = GuardState.fromJson({
        'claude_down_since': DateTime.now().toIso8601String(),
        'claude_down_until': DateTime.now()
            .add(const Duration(hours: 3))
            .toIso8601String(),
      });
      await showTab(
        tester,
        panel(
          session(),
          state: state,
          pace: Pace.fromJson(const {
            'today_required': 30,
            'pages_today': 0,
            'bonus_today': false,
          }),
        ),
      );
      expect(find.byType(GraderNoteChip), findsOneWidget);
      expect(spoken('gaming bonus'), findsOneWidget);
      expectNoWords(tester, content: readContent);
    });

    for (final answer in [
      const GuardResponse(ok: true, code: 'passed', passed: true),
      const GuardResponse(ok: true, code: 'ungraded', passed: true),
      const GuardResponse(
        ok: true,
        code: 'failed',
        passed: false,
        data: {
          'missing': ['the habit loop'],
        },
      ),
      const GuardResponse(ok: false, code: 'not_yet'),
      const GuardResponse(ok: true, code: 'queued'),
      // An old PC's sentence-only reply: neutral glyph, never the sentence.
      GuardResponse.fromJson(const {'ok': true, 'message': 'Credited 18.'}),
    ]) {
      testWidgets('the verdict ${answer.code}', (tester) async {
        api.onSend = (_) async => answer;
        await showTab(tester, panel(session()));
        await tester.enterText(find.byType(TextField), 'x' * 160);
        await tester.tap(spoken('Submit summary'));
        await settle(tester, 10);
        expectNoWords(tester, content: readContent);
      });
    }

    testWidgets('a send that failed', (tester) async {
      api.onSend = (_) async => throw shareDown();
      await showTab(tester, panel(session()));
      await tester.tap(spoken('Submit summary'));
      await settle(tester, 10);
      expectNoWords(tester, content: readContent);
    });
  });
}
