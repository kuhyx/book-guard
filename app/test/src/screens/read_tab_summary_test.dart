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

  Future<void> pump(WidgetTester tester) => pumpTab(
    tester,
    ReadTab(
      api: api,
      state: sampleState(),
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

  testWidgets('a passed summary is a green tick and cleared', (tester) async {
    final answer = Completer<GuardResponse>();
    api.onSend = (_) => answer.future;
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
    await tester.pump();
    expect(busyBar(), findsOneWidget);
    final button = tester.widget<FilledButton>(buttonSpoken('Submit summary'));
    expect(button.onPressed, isNull);

    answer.complete(const GuardResponse(ok: true, passed: true));
    await settle(tester);
    expect(api.sent.single.type, 'summary');
    expect(api.sent.single.body, {
      'session_id': 'session:c-d',
      'summary': 'Kaladin trains.',
    });
    expect(busyBar(), findsNothing);
    expect(cueOf(CueKind.ok), findsOneWidget);
    expect(cueOf(CueKind.error), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
    expect(changed, 1);
  });

  testWidgets(
    'a failed summary is a red cross, the topics, and kept for editing',
    (tester) async {
      api.onSend = (_) async => const GuardResponse(
        ok: true,
        code: 'failed',
        passed: false,
        data: {
          'missing': ['the habit loop', 'Kaladin'],
        },
      );
      await pump(tester);
      await submit(tester, 'stuff happened');
      await settle(tester);
      expect(cueOf(CueKind.error), findsOneWidget);
      // How many topics are missing, then each one quoted; a retry arrow.
      expect(
        find.descendant(of: cueOf(CueKind.error), matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.text('“the habit loop”'), findsOneWidget);
      expect(find.text('“Kaladin”'), findsOneWidget);
      expect(spoken('rewrite'), findsOneWidget);
      expect(find.text('stuff happened'), findsOneWidget);
    },
  );

  testWidgets('an unanswered request is neutral', (tester) async {
    api.onSend = (_) async => const GuardResponse(ok: false, code: 'not_yet');
    await pump(tester);
    await submit(tester, 'text');
    await settle(tester);
    expect(cueOf(CueKind.warn), findsOneWidget);
    expect(cueOf(CueKind.ok), findsNothing);
    expect(cueOf(CueKind.error), findsNothing);
    expect(find.text('text'), findsOneWidget);
  });

  testWidgets('a send failure shows an error and keeps grading text', (
    tester,
  ) async {
    api.onSend = (_) async => throw shareDown();
    await pump(tester);
    await submit(tester, 'text');
    await settle(tester);
    expect(cueOf(CueKind.error), findsOneWidget);
    expect(busyBar(), findsNothing);
    expect(changed, 1);
  });

  testWidgets('leaving mid-grading does not touch the dead tab', (
    tester,
  ) async {
    final answer = Completer<GuardResponse>();
    api.onSend = (_) => answer.future;
    await pump(tester);
    await submit(tester, 'text');
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    answer.complete(const GuardResponse(ok: true, code: 'passed'));
    await settle(tester);
    expect(find.byType(StatusCue), findsNothing);
    expect(changed, 1);
  });
}
