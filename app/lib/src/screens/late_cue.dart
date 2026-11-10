import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:flutter/material.dart';

/// The one cue for several late answers: the worst kind wins (error, then
/// warn, info, ok), because a second snackbar would hide the first. A reply
/// the app has no glyph for that also failed is an error, not information.
Cue worstCue(List<LateAnswer> answers) {
  Cue pick(LateAnswer a) {
    final cue = replyCue(a.response);
    final unknownFailure =
        identical(cue, unknownReply) &&
        (!a.response.ok || a.response.passed == false);
    return unknownFailure
        ? Cue(
            CueKind.error,
            icon: unknownReply.icon,
            semanticLabel: unknownReply.semanticLabel,
          )
        : cue;
  }

  return [
    for (final a in answers) pick(a),
  ].reduce((worst, next) => next.kind.index > worst.kind.index ? next : worst);
}

/// Shows [answers] as one icon snackbar; the number of answers (or the page
/// of a lone boxed photo) sits beside the glyph.
void showLateAnswers(BuildContext context, List<LateAnswer> answers) {
  if (answers.isEmpty) return;
  final count = answers.length;
  final page = count == 1 ? answers.single.response.number('page') : null;
  final shown = count > 1 ? count : page;
  showCue(
    context,
    worstCue(answers),
    badge: shown == null ? null : Text('$shown'),
  );
}
