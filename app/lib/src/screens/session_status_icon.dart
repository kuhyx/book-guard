/// A session's status as a glyph and a tint, never a word: the PC's status
/// strings (`needs-quiz`, `credited`, ...) pick the icon, the words survive
/// only as the spoken label.
library;

import 'package:book_guard_app/src/session_info.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The status key that picks the glyph for [session]: a failed summary
/// waiting for its rewrite is `retry`, whatever the ledger status says.
String statusKey(SessionInfo session) =>
    session.retry != null ? 'retry' : session.status;

/// The glyph for a PC session status (see [statusKey]); unknown ones get a
/// neutral question mark.
IconData iconFor(String status) => switch (status) {
  'needs-check-photo' => Icons.photo_camera,
  'needs-quiz' => Icons.edit,
  'credited' => Icons.check_circle,
  'retry' => Icons.replay,
  'failed-quiz' => Icons.cancel,
  'too-fast' => Icons.fast_forward,
  _ => Icons.help_outline,
};

/// The tint for a PC session status: green done, amber waiting on the
/// reader, red not counted, grey unknown.
Color tintFor(BuildContext context, String status) {
  final colors = context.statusColors;
  return switch (status) {
    'credited' => colors.success,
    'needs-check-photo' || 'needs-quiz' || 'retry' => colors.warning,
    'failed-quiz' || 'too-fast' => colors.danger,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

/// The words a screen reader speaks for [status]; never painted.
String spokenLabel(String status) => switch (status) {
  'needs-check-photo' => 'photograph the check page',
  'needs-quiz' => 'write the summary',
  'credited' => 'credited',
  'retry' => 'summary failed: rewrite it',
  'failed-quiz' => 'not counted: summary failed',
  'too-fast' => 'not counted: under 50 s per page',
  _ => status,
};

/// The spoken status of [session]; a failed summary waiting for its rewrite
/// says so. Never painted: a row shows [SessionStatusIcon].
String statusText(SessionInfo session) => spokenLabel(statusKey(session));

/// [status] as a tinted glyph that speaks its label.
class SessionStatusIcon extends StatelessWidget {
  /// Creates the glyph for [status].
  const new(this.status, {this.size, super.key});

  /// A PC session status, or `retry` (see [statusKey]).
  final String status;

  /// Glyph size; the icon theme's when null.
  final double? size;

  @override
  Widget build(BuildContext context) => Icon(
    iconFor(status),
    size: size,
    color: tintFor(context, status),
    semanticLabel: spokenLabel(status),
  );
}
