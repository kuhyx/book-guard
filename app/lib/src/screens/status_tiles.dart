import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/fit_sheet.dart';
import 'package:book_guard_app/src/screens/icon_num.dart';
import 'package:book_guard_app/src/screens/pace_panel.dart';
import 'package:book_guard_app/src/screens/session_rows.dart';
import 'package:book_guard_app/src/screens/session_screen.dart';
import 'package:book_guard_app/src/screens/session_status_icon.dart';
import 'package:book_guard_app/src/screens/status_cards.dart';
import 'package:book_guard_app/src/screens/todo_rows.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// How many of the newest sessions get a tile of their own; the rest wait
/// behind the all-sessions tile.
const recentSessions = 6;

/// The pace card; a tap opens the week, month and simulation cells in a
/// sheet, so the tab itself never scrolls.
class PaceTile extends StatelessWidget {
  /// Creates the tile.
  const new({required this.state, super.key});

  /// The snapshot whose pace is shown.
  final GuardState state;

  @override
  Widget build(BuildContext context) {
    final inputs = state.paceInputs;
    final card = PaceCard(pace: state.pace);
    if (inputs == null) return card;
    return InkWell(
      onTap: () => showFitSheet(context, PacePanel(inputs: inputs)),
      child: Stack(
        children: [
          card,
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Icon(
              Icons.unfold_more,
              color: Theme.of(context).hintColor,
              semanticLabel: 'pace details',
            ),
          ),
        ],
      ),
    );
  }
}

/// The to-do lines and the newest sessions as two columns of tiles that
/// fill what is left of the tab and page sideways past it.
class StatusTiles extends StatelessWidget {
  /// Creates the tiles.
  const new({required this.state, super.key, this.api});

  /// The snapshot.
  final GuardState state;

  /// For opening a session's history; null hides the link.
  final GuardApi? api;

  @override
  Widget build(BuildContext context) {
    final sessions = state.sessions.reversed.toList();
    final tiles = <Widget>[
      for (final t in state.todo) _TodoTile(t),
      for (final s in sessions.take(recentSessions))
        _SessionTile(session: s, api: api),
      if (sessions.length > recentSessions)
        _AllSessionsTile(sessions: sessions, api: api),
    ];
    return FitGrid(
      columns: 2,
      minSquare: 0.35,
      padding: EdgeInsets.zero,
      itemCount: tiles.length,
      itemBuilder: (context, i) => tiles[i],
    );
  }
}

/// A tile: a card whose content shrinks to fit rather than overflow.
class _Tile extends StatelessWidget {
  const new({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      ),
    ),
  );
}

/// One to-do line: its glyphs and numbers, the line itself only spoken.
class _TodoTile extends StatelessWidget {
  const new(this.line);

  final String line;

  @override
  Widget build(BuildContext context) {
    final item = TodoItem.parse(line);
    return Semantics(
      label: line,
      child: ExcludeSemantics(
        child: _Tile(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, color: context.statusColors.warning),
              if (item.extra case final extra?) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(extra, size: 20),
              ],
              for (final n in item.numbers) ...[
                const SizedBox(width: AppSpacing.sm),
                IconNum(pagesGlyph, n),
              ],
              if (item.clock case final clock?) ...[
                const SizedBox(width: AppSpacing.sm),
                IconNum(minutesGlyph, clock),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One session: status glyph and range on top, pages and minutes below;
/// a tap opens its history when there is one.
class _SessionTile extends StatelessWidget {
  const new({required this.session, required this.api});

  final SessionInfo session;
  final GuardApi? api;

  @override
  Widget build(BuildContext context) {
    final api = this.api;
    final open = api != null && session.detail.isNotEmpty;
    return _Tile(
      onTap: open
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SessionScreen(api: api, session: session),
              ),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SessionStatusIcon(statusKey(session), size: 24),
              const SizedBox(width: AppSpacing.sm),
              IconNum(
                Icons.import_contacts,
                '${session.estimated ? '≈' : ''}'
                '${session.startPage}-${session.endPage}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconNum(pagesGlyph, '${session.pages}'),
              const SizedBox(width: AppSpacing.md),
              IconNum(minutesGlyph, '${session.minutes}'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Every session, newest first, in a sheet; each row still opens its
/// history.
class _AllSessionsTile extends StatelessWidget {
  const new({required this.sessions, required this.api});

  final List<SessionInfo> sessions;
  final GuardApi? api;

  @override
  Widget build(BuildContext context) => _Tile(
    onTap: () => showFitSheet(
      context,
      Column(
        children: [for (final s in sessions) SessionRow(session: s, api: api)],
      ),
    ),
    child: IconNum(
      Icons.history,
      '${sessions.length}',
      semanticLabel: 'all sessions',
    ),
  );
}
