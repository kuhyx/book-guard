import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/grader_note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

GuardState _down({String? until, String since = '2026-10-18T08:25:00'}) =>
    GuardState.fromJson({
      'claude_down_since': since,
      'claude_down_until': ?until,
    });

void main() {
  final now = DateTime(2026, 10, 18, 9);

  test('the PC exports when the outage ends', () {
    expect(
      _down(until: '2026-10-18T16:40:00').claudeDownUntil,
      DateTime(2026, 10, 18, 16, 40),
    );
    expect(_down().claudeDownUntil, isNull);
  });

  test('hidden while no summary waits for its verdict', () {
    expect(graderNote(_down(), waiting: false, now: now), isNull);
    expect(graderNote(null, waiting: true, now: now), isNull);
    expect(
      graderNote(GuardState.fromJson(const {}), waiting: true, now: now),
      isNull,
    );
  });

  test('hidden from the instant the reset time passes', () {
    final state = _down(until: '2026-10-18T09:00:00');
    expect(
      graderNote(state, waiting: true, now: now.subtract(_second)),
      isNotNull,
    );
    expect(graderNote(state, waiting: true, now: now), isNull);
  });

  test('today: the times, as numerals only', () {
    final note = graderNote(
      _down(until: '2026-10-18T16:40:00'),
      waiting: true,
      now: now,
    )!;
    expect((note.since, note.until), ('08:25', '16:40'));
    expect(graderNote(_down(), waiting: true, now: now)!.until, isNull);
  });

  test('another day names the date as numerals', () {
    String? since(String at) =>
        graderNote(_down(since: at), waiting: true, now: now)?.since;
    expect(since('2026-10-17T16:25:00'), '17.10 16:25');
    expect(since('2026-10-15T16:25:00'), '15.10 16:25');
    expect(
      graderNote(
        _down(until: '2026-10-19T16:40:00'),
        waiting: true,
        now: now,
      )?.until,
      '19.10 16:40',
    );
  });

  // An outage that runs past midnight has a date on both ends; the chip
  // must fit the Read tab's 284 px summary column, wrapping, not overflowing.
  testWidgets('dates on both ends still fit a narrow column', (tester) async {
    const note = GraderNote(since: '17.10 21:26', until: '18.10 00:26');
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 300, child: GraderNoteChip(note)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('17.10 21:26 - 18.10 00:26'), findsOneWidget);
  });
}

const _second = Duration(seconds: 1);
