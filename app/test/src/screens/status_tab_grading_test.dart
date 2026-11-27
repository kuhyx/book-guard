import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_a.dart';
import '../../support/states.dart';
import '../../support/status_pump.dart';

// A summary out with the grader is done on the phone (kuhy, 2026-11-27:
// never wait on the PC): the Status tab must not ask for it again.
void main() {
  final state = sampleState({
    'todo': const ['WRITE A SUMMARY at the PC for p. 63-80'],
    'sessions': [
      {'id': 'o', 'start_page': 63, 'end_page': 80, 'status': 'needs-quiz'},
    ],
  });

  Future<void> pump(WidgetTester tester, Set<String> grading) {
    tallPhone(tester);
    return pumpTab(
      tester,
      StatusTab(state: state, error: null, grading: grading),
    );
  }

  testWidgets('an unsent summary is asked for', (tester) async {
    await pump(tester, const {});
    expect(iconLabeled('write the summary'), findsOneWidget);
    expect(
      find.bySemanticsLabel('WRITE A SUMMARY at the PC for p. 63-80'),
      findsOneWidget,
    );
    expect(iconLabeled('summary sent: grading'), findsNothing);
  });

  testWidgets('a sent summary shows as grading, never asked again', (
    tester,
  ) async {
    await pump(tester, const {'o'});
    expect(iconLabeled('summary sent: grading'), findsOneWidget);
    expect(iconLabeled('write the summary'), findsNothing);
    expect(
      find.bySemanticsLabel('WRITE A SUMMARY at the PC for p. 63-80'),
      findsNothing,
    );
    expect(find.text('63-80'), findsOneWidget);
  });

  testWidgets("another session's ask stays while one is grading", (
    tester,
  ) async {
    tallPhone(tester);
    await pumpTab(
      tester,
      StatusTab(
        state: sampleState({
          'todo': const [
            'WRITE A SUMMARY at the PC for p. 63-80',
            'REWRITE THE SUMMARY at the PC for p. 1-9',
          ],
          'sessions': [
            {'id': 'a', 'start_page': 1, 'end_page': 9, 'status': 'needs-quiz'},
            {
              'id': 'o',
              'start_page': 63,
              'end_page': 80,
              'status': 'needs-quiz',
            },
          ],
        }),
        error: null,
        grading: const {'o'},
      ),
    );
    expect(
      find.bySemanticsLabel('REWRITE THE SUMMARY at the PC for p. 1-9'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('WRITE A SUMMARY at the PC for p. 63-80'),
      findsNothing,
    );
  });
}
