import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/finders_read.dart';
import '../../support/states.dart';

void main() {
  late FakeApi api;
  late int changed;

  setUp(() {
    api = FakeApi();
    changed = 0;
  });

  // One session at a time: only the session waiting for its summary, so the
  // summary is the tab's one step.
  Future<void> pump(WidgetTester tester) => pumpTab(
    tester,
    ReadTab(
      api: api,
      state: sampleState({
        'sessions': [
          {'id': 'session:c-d', 'status': 'needs-quiz', 'start_page': '21'},
        ],
      }),
      desktop: false,
      onChanged: () async => changed++,
      photoSource: ({required camera}) async => null,
    ),
  );

  Future<void> submit(WidgetTester tester, String text) async {
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tapVisible(tester, spoken('Submit summary'));
  }

  testWidgets('no summary section without a session waiting for one', (
    tester,
  ) async {
    await pumpTab(
      tester,
      ReadTab(
        api: api,
        state: sampleState({'sessions': const <Object>[]}),
        desktop: false,
        onChanged: () async {},
      ),
    );
    expect(spoken('Submit summary'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a sent summary is queued at once, never waited on', (
    tester,
  ) async {
    // kuhy, 2026-11-24: never wait on the PC. The verdict arrives later as
    // a late answer; nothing here asks the PC.
    var asked = false;
    api.onSend = (_) {
      asked = true;
      return Completer<GuardResponse>().future;
    };
    await pump(tester);
    // The page range is on the submit button, as numerals.
    expect(
      find.descendant(
        of: buttonSpoken('Submit summary'),
        matching: find.text('21-0'),
      ),
      findsOneWidget,
    );
    await submit(tester, '  Kaladin trains.  ');
    await settle(tester);
    expect(asked, isFalse);
    expect(api.sent.single.type, 'summary');
    expect(api.sent.single.body, {
      'session_id': 'session:c-d',
      'summary': 'Kaladin trains.',
    });
    // The home screen refreshes at once and moves the tab on.
    expect(changed, 1);
    expect(buttonSpoken('Submit summary'), findsNothing);
    expect(cueOf(CueKind.error), findsNothing);
  });

  testWidgets('a summary with the grader frees the next start', (tester) async {
    await pumpTab(
      tester,
      ReadTab(
        api: api,
        state: sampleState({
          'open_start': null,
          'sessions': [
            {'id': 'session:c-d', 'status': 'needs-quiz', 'start_page': '21'},
          ],
        }),
        desktop: false,
        onChanged: () async {},
        grading: const {'session:c-d'},
      ),
    );
    expect(spoken('Submit summary'), findsNothing);
    expect(spoken('Start reading'), findsOneWidget);
  });

  testWidgets('a summary the phone cannot queue shows an error, text kept', (
    tester,
  ) async {
    api.queueError = shareDown();
    await pump(tester);
    await submit(tester, 'text');
    await settle(tester);
    expect(cueOf(CueKind.error), findsOneWidget);
    expect(busyBar(), findsNothing);
    expect(find.text('text'), findsOneWidget);
    expect(changed, 1);
  });
}
