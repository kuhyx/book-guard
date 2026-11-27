import 'package:book_guard_app/src/capture.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/next_step.dart';
import 'package:flutter_test/flutter_test.dart';

// One session at a time: the Read tab offers exactly one next step, the
// oldest unfinished session's.

SessionInfo _session(String id, {required String status, int day = 1}) =>
    SessionInfo(
      id: id,
      startPage: 1,
      endPage: 40,
      checkPage: null,
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

/// An hour after the test captures were taken.
final _now = DateTime.utc(2026, 11, 21, 16);

void main() {
  test('nothing open: the start photo', () {
    final step = nextStep(openStart: null, quiz: [], captures: [], now: _now);
    expect(step.kind, StepKind.start);
    expect(step.label, 'start');
  });

  test('reading: the stop photo, never a start', () {
    final step = nextStep(openStart: 59, quiz: [], captures: [], now: _now);
    expect(step.kind, StepKind.stop);
    expect(step.label, 'stop');
  });

  test('the oldest owed summary comes before a stop', () {
    final step = nextStep(
      openStart: 300,
      quiz: [
        _session('b', status: 'needs-quiz', day: 21),
        _session('c', status: 'needs-quiz', day: 19),
      ],
      captures: [],
      now: _now,
    );
    expect(step.kind, StepKind.summary);
    expect(step.session?.id, 'c');
    expect(step.label, isNull);
  });

  test('no check page is ever asked for', () {
    // 2026-11-27: the check photo is gone; a stop opens the summary.
    expect(StepKind.values, [StepKind.start, StepKind.stop, StepKind.summary]);
  });

  test('a stored photo for the step finishes it; others stay hidden', () {
    final step = nextStep(
      openStart: 12,
      quiz: [],
      captures: [_capture('start'), _capture('stop'), _capture('check237')],
      now: _now,
    );
    expect(step.kind, StepKind.stop);
    expect(step.capture?.label, 'stop');
  });

  test('a stored photo of a finished step is not offered', () {
    final step = nextStep(
      openStart: null,
      quiz: [],
      captures: [_capture('check237')],
      now: _now,
    );
    expect(step.kind, StepKind.start);
    expect(step.capture, isNull);
  });

  test('a stored photo 12 h or older never stands in for the camera', () {
    // 2026-11-22: a start photo of 2026-10-27 hid the camera for 26 days.
    final old = Capture(
      id: 'old',
      label: 'start',
      fileName: 'old.jpg',
      takenAt: DateTime.utc(2026, 10, 27, 19, 15),
    );
    final step = nextStep(
      openStart: null,
      quiz: [],
      captures: [old],
      now: DateTime.utc(2026, 11, 22, 10, 30),
    );
    expect(step.kind, StepKind.start);
    expect(step.capture, isNull);
    final edge = nextStep(
      openStart: null,
      quiz: [],
      captures: [_capture('start')],
      now: DateTime.utc(2026, 11, 22, 3),
    );
    expect(edge.capture, isNull);
    expect(staleCaptures([old, _capture('stop')], _now), [old]);
  });
}
