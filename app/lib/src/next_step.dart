/// One session at a time: the Read tab's single next step.
library;

import 'package:book_guard_app/src/capture.dart';
import 'package:book_guard_app/src/session_info.dart';

/// What the reader does next.
enum StepKind {
  /// Photograph the page reading starts on.
  start,

  /// Photograph the page reading stopped on.
  stop,

  /// Write the summary (no check page since 2026-11-27: a stop opens it).
  summary,
}

/// The one thing the Read tab offers.
class NextStep {
  /// Creates the step.
  const new(this.kind, {this.session, this.capture});

  /// What to do.
  final StepKind kind;

  /// The unfinished session it belongs to (summary only).
  final SessionInfo? session;

  /// A photo for this very step that came back from the camera under
  /// [freshFor] ago and was never sent: offered beside the camera, never
  /// in its place.
  final Capture? capture;

  /// The photo label (`start`, `stop`); null for a summary.
  String? get label => switch (kind) {
    StepKind.start => 'start',
    StepKind.stop => 'stop',
    StepKind.summary => null,
  };
}

final _never = DateTime.utc(9999);

/// How long a stored photo may stand beside the camera as its step's photo.
/// Older ones go to the failed photos (2026-11-22: a start photo of
/// 2026-10-27 stood in for the camera for 26 days).
const freshFor = Duration(hours: 12);

bool _fresh(Capture c, DateTime now) => now.difference(c.takenAt) < freshFor;

/// The stored photos [freshFor] or older at [now]: never a session photo.
List<Capture> staleCaptures(List<Capture> captures, DateTime now) => [
  for (final c in captures)
    if (!_fresh(c, now)) c,
];

/// The oldest unfinished session's summary; with none unfinished, the stop
/// photo while reading, else the start photo -- so a new session never
/// starts while one is unfinished. A stored capture is offered only when its
/// label is that step's and it is under [freshFor] old at [now].
NextStep nextStep({
  required int? openStart,
  required List<SessionInfo> quiz,
  required List<Capture> captures,
  required DateTime now,
}) {
  // Stable: equal times keep the list's order.
  final indexed = quiz.indexed.toList()
    ..sort((a, b) {
      final at = (a.$2.startedAt ?? _never).compareTo(b.$2.startedAt ?? _never);
      return at != 0 ? at : a.$1.compareTo(b.$1);
    });
  final step = indexed.isNotEmpty
      ? NextStep(StepKind.summary, session: indexed.first.$2)
      : NextStep(openStart == null ? StepKind.start : StepKind.stop);
  final label = step.label;
  if (label == null) return step;
  final stored = captures
      .where((c) => c.label == label && _fresh(c, now))
      .firstOrNull;
  return stored == null
      ? step
      : NextStep(step.kind, session: step.session, capture: stored);
}
