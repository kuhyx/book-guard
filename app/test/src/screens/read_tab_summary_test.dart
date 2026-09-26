import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/states.dart';

const _grading = 'Grading - this takes up to a minute...';

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
    await tapVisible(tester, find.text('Submit summary'));
  }

  Color? verdictColor(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

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
    expect(find.text('Submit summary'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a passed summary is shown in green and cleared', (tester) async {
    final answer = Completer<GuardResponse>();
    api.onSend = (_) => answer.future;
    await pump(tester);
    expect(find.text('Summary for p. 21-0'), findsOneWidget);
    await submit(tester, '  Kaladin trains.  ');
    await tester.pump();
    expect(find.text(_grading), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit summary'),
    );
    expect(button.onPressed, isNull);

    answer.complete(
      const GuardResponse(ok: true, message: 'Credited', passed: true),
    );
    await settle(tester);
    expect(api.sent.single.type, 'summary');
    expect(api.sent.single.body, {
      'session_id': 'session:c-d',
      'summary': 'Kaladin trains.',
    });
    expect(find.text(_grading), findsNothing);
    final theme = Theme.of(tester.element(find.text('Credited')));
    expect(
      verdictColor(tester, 'Credited'),
      theme.extension<AppStatusColors>()?.success,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
    expect(changed, 1);
  });

  testWidgets('a failed summary is red and kept for editing', (tester) async {
    api.onSend = (_) async =>
        const GuardResponse(ok: true, message: 'Too vague', passed: false);
    await pump(tester);
    await submit(tester, 'stuff happened');
    await settle(tester);
    final theme = Theme.of(tester.element(find.text('Too vague')));
    expect(verdictColor(tester, 'Too vague'), theme.colorScheme.error);
    expect(find.text('stuff happened'), findsOneWidget);
  });

  testWidgets('an unanswered request is neutral', (tester) async {
    api.onSend = (_) async =>
        const GuardResponse(ok: false, message: 'PC is off');
    await pump(tester);
    await submit(tester, 'text');
    await settle(tester);
    expect(verdictColor(tester, 'PC is off'), isNull);
    expect(find.text('text'), findsOneWidget);
  });

  testWidgets('a send failure shows an error and keeps grading text', (
    tester,
  ) async {
    api.onSend = (_) async => throw shareDown();
    await pump(tester);
    await submit(tester, 'text');
    await settle(tester);
    expect(find.text('dufs Reading/x failed (500)'), findsOneWidget);
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
    answer.complete(const GuardResponse(ok: true, message: 'late'));
    await settle(tester);
    expect(find.text('late'), findsNothing);
    expect(changed, 1);
  });
}
