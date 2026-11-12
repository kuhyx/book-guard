import 'package:book_guard_app/src/guard_response.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The cue for the grader's answer: the reply's own code when it has one,
/// else its `passed` flag (an old PC), else the neutral glyph.
Cue summaryCue(GuardResponse response) {
  if (response.code != null) return replyCue(response);
  return switch (response.passed) {
    true => const Cue(CueKind.ok, semanticLabel: 'credited'),
    false => const Cue(
      CueKind.error,
      icon: Icons.cancel,
      semanticLabel: 'not accepted',
    ),
    null => unknownReply,
  };
}

/// The grader's verdict as glyphs. A pass is a green tick (with the pages
/// credited); a fail is a red cross, how many topics are missing, a retry
/// arrow and the topics themselves, quoted like a book title.
class SummaryVerdict extends StatelessWidget {
  /// Creates the verdict for [cue].
  const new(
    this.cue, {
    super.key,
    this.pages,
    this.missing = const [],
    this.retry = false,
  });

  /// The verdict the PC's reply [response] carries; [pages] are the pages a
  /// pass credits.
  factory reply(GuardResponse response, {int? pages}) {
    final cue = summaryCue(response);
    final failed = response.passed == false || response.code == 'failed';
    final passed = response.passed == true || response.code == 'passed';
    return SummaryVerdict(
      cue,
      pages: passed && (pages ?? 0) > 0 ? pages : null,
      missing: failed ? response.missing : const [],
      retry: failed,
    );
  }

  /// What it means.
  final Cue cue;

  /// Pages a pass credits, when known.
  final int? pages;

  /// Topics to add on a fail.
  final List<String> missing;

  /// Whether the summary can be rewritten and sent again.
  final bool retry;

  @override
  Widget build(BuildContext context) {
    final pages = this.pages;
    final count = missing.length;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusCue(
            cue,
            badge: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pages != null) Text('$pages'),
                if (count > 0) Text('$count'),
                if (retry) ...[
                  if (count > 0 || pages != null)
                    const SizedBox(width: AppSpacing.sm),
                  const Icon(Icons.refresh, semanticLabel: 'rewrite'),
                ],
              ],
            ),
          ),
          for (final topic in missing)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text('“$topic”'),
            ),
        ],
      ),
    );
  }
}
