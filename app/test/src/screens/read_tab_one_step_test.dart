import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_read.dart';
import '../../support/states.dart';

// One session at a time: the Read tab shows exactly one step.

void main() {
  Future<void> pump(WidgetTester tester, Map<String, dynamic> over) => pumpTab(
    tester,
    ReadTab(
      api: FakeApi(),
      state: sampleState(over),
      desktop: false,
      onChanged: () async {},
      photoSource: ({required camera}) async => null,
    ),
  );

  int actions() => [
    'Start reading',
    'Stop reading',
    'Photograph the check page',
    'Finish the stored photo',
    'Submit summary',
  ].where((l) => spoken(l).evaluate().isNotEmpty).length;

  testWidgets('a check owed, a summary owed and reading: only the check', (
    tester,
  ) async {
    await pump(tester, const {});
    expect(spoken('Photograph the check page'), findsOneWidget);
    expect(actions(), 1);
  });

  testWidgets('a summary owed: only the summary, no new start', (tester) async {
    await pump(tester, {
      'open_start': null,
      'sessions': [
        {'id': 'session:c-d', 'status': 'needs-quiz', 'start_page': '21'},
      ],
    });
    expect(spoken('Submit summary'), findsOneWidget);
    expect(spoken('Start reading'), findsNothing);
    expect(actions(), 1);
  });

  testWidgets('nothing unfinished: only the start', (tester) async {
    await pump(tester, {'open_start': null, 'sessions': const <Object>[]});
    expect(spoken('Start reading'), findsOneWidget);
    expect(actions(), 1);
  });
}
