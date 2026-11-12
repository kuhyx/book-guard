import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/icon_num.dart';
import 'package:book_guard_app/src/screens/status_cards.dart';
import 'package:book_guard_app/src/screens/status_tiles.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

export 'package:book_guard_app/src/screens/session_status_icon.dart'
    show statusText;

/// Pace, what to do next, and recent sessions: glyphs and numbers only,
/// fitted to one screen -- the pace cells and older sessions sit in sheets,
/// tiles past the screen page sideways. The app bar's refresh refetches.
class StatusTab extends StatelessWidget {
  /// Creates the tab.
  const new({
    required this.state,
    required this.error,
    super.key,
    this.api,
    this.waiting = 0,
  });

  /// The latest snapshot, or null before one arrived.
  final GuardState? state;

  /// The last fetch error, if any.
  final Object? error;

  /// For opening a session's history; null hides the link.
  final GuardApi? api;

  /// Items still waiting on the phone for the PC.
  final int waiting;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            _ErrorCard(error: error!, since: s?.generatedAt, waiting: waiting),
          if (s == null && error == null) const _Waiting(),
          if (s != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: LockMark(locked: s.locked, reason: s.reason),
            ),
            const SizedBox(height: AppSpacing.sm),
            PaceTile(state: s),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: StatusTiles(state: s, api: api),
            ),
          ],
        ],
      ),
    );
  }
}

/// Before the first snapshot: an hourglass.
class _Waiting extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Center(
      child: Icon(
        Icons.hourglass_empty,
        size: 96,
        color: Theme.of(context).hintColor,
        semanticLabel: 'waiting for the PC',
      ),
    ),
  );
}

/// A failed fetch: an unreachable PC is the cloud glyph with when the shown
/// snapshot is from and how much waits on the phone; any other failure is
/// the error glyph (with the HTTP status when it has one).
class _ErrorCard extends StatelessWidget {
  const new({required this.error, required this.since, required this.waiting});

  final Object error;
  final DateTime? since;
  final int waiting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = error is DavException ? (error as DavException).status : -1;
    final offline = status == 0;
    final at = since?.toLocal();
    final tint = theme.colorScheme.onErrorContainer;
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              offline ? Icons.cloud_off : Icons.error,
              color: tint,
              semanticLabel: offline ? 'PC unreachable' : 'request failed',
            ),
            if (status > 0) IconNum(Icons.http, '$status', tint: tint),
            if (offline && at != null)
              IconNum(
                Icons.history,
                '${at.day.toString().padLeft(2, '0')}.'
                '${at.month.toString().padLeft(2, '0')} '
                '${at.hour.toString().padLeft(2, '0')}:'
                '${at.minute.toString().padLeft(2, '0')}',
                tint: tint,
              ),
            if (offline && waiting > 0)
              IconNum(Icons.outbox, '$waiting', tint: tint),
          ],
        ),
      ),
    );
  }
}
