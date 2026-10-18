import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/grader_note.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('today: the time, when it is back, and who grades instead', () {
    final note = graderNote(
      _down(until: '2026-10-18T16:40:00'),
      waiting: true,
      now: now,
    );
    expect(note, contains('since 08:25'));
    expect(note, contains('until 16:40'));
    expect(note, contains('local model'));
    expect(note, isNot(contains('once it is back')));
  });

  test('another day names the date', () {
    String? since(String at) =>
        graderNote(_down(since: at), waiting: true, now: now);
    expect(since('2026-10-17T16:25:00'), contains('since yesterday 16:25'));
    expect(since('2026-10-15T16:25:00'), contains('since 15.10 16:25'));
    expect(
      graderNote(_down(until: '2026-10-19T16:40:00'), waiting: true, now: now),
      contains('until tomorrow 16:40'),
    );
  });
}

const _second = Duration(seconds: 1);
