import 'package:book_guard_app/src/capture.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/next_step.dart';
import 'package:flutter_test/flutter_test.dart';

// One session at a time: the Read tab offers exactly one next step, the
// oldest unfinished session's.

SessionInfo _session(
  String id, {
  required String status,
  int? check,
  int day = 1,
}) => SessionInfo(
  id: id,
  startPage: 1,
  endPage: 40,
  checkPage: check,
  pages: 40,
  minutes: 60,
  startedAt: DateTime.utc(2026, 11, day, 10),
  status: status,
);

Capture _capture(String label) => Capture(
  id: label,
  label: label,
  fileName: '$label.jpg',
  takenAt: DateTime.utc(2026, 11, 21, 15),
);

void main() {
  test('nothing open: the start photo', () {
    final step = nextStep(openStart: null, checks: [], quiz: [], captures: []);
    expect(step.kind, StepKind.start);
    expect(step.label, 'start');
  });

  test('reading: the stop photo, never a start', () {
    final step = nextStep(openStart: 59, checks: [], quiz: [], captures: []);
    expect(step.kind, StepKind.stop);
    expect(step.label, 'stop');
  });

  test('a check page owed comes before a summary and a stop', () {
    final step = nextStep(
      openStart: 300,
      checks: [
        _session('b', check: 237, status: 'needs-check-photo', day: 21),
        _session('a', check: 12, status: 'needs-check-photo', day: 20),
      ],
      quiz: [_session('c', status: 'needs-quiz', day: 19)],
      captures: [],
    );
    // The oldest unfinished session first: c (day 19) waits for its summary.
    expect(step.kind, StepKind.summary);
    expect(step.session?.id, 'c');
  });

  test('the oldest check first when no summary is older', () {
    final step = nextStep(
      openStart: null,
      checks: [
        _session('b', check: 237, status: 'needs-check-photo', day: 21),
        _session('a', check: 12, status: 'needs-check-photo', day: 20),
      ],
      quiz: [_session('c', status: 'needs-quiz', day: 22)],
      captures: [],
    );
    expect(step.kind, StepKind.check);
    expect(step.session?.id, 'a');
    expect(step.label, 'check12');
  });

  test('a stored photo for the step finishes it; others stay hidden', () {
    final step = nextStep(
      openStart: null,
      checks: [_session('a', check: 237, status: 'needs-check-photo')],
      quiz: [],
      captures: [_capture('stop'), _capture('check237')],
    );
    expect(step.kind, StepKind.check);
    expect(step.capture?.label, 'check237');
  });

  test('a stored photo of a finished step is not offered', () {
    final step = nextStep(
      openStart: null,
      checks: [],
      quiz: [],
      captures: [_capture('check237')],
    );
    expect(step.kind, StepKind.start);
    expect(step.capture, isNull);
  });
}
