import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/session_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Human text for each session status the PC reports.
const sessionStatusText = {
  'needs-check-photo': 'photograph the check page',
  'needs-quiz': 'write the summary',
  'credited': 'credited',
  'failed-quiz': 'not counted: summary failed',
  'too-fast': 'not counted: under 50 s per page',
};

/// Pace, what to do next, and recent sessions.
class StatusTab extends StatelessWidget {
  /// Creates the tab.
  const new({
    required this.state,
    required this.error,
    required this.onRefresh,
    super.key,
    this.api,
  });

  /// The latest snapshot, or null before one arrived.
  final GuardState? state;

  /// The last fetch error, if any.
  final Object? error;

  /// Pull-to-refresh.
  final Future<void> Function() onRefresh;

  /// For opening a session's history; null hides the link.
  final GuardApi? api;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text('$error'),
              ),
            ),
          if (s == null && error == null)
            const EmptyState(
              icon: Icons.hourglass_empty,
              title: 'Waiting for the PC',
              message: 'book-guard has not written its status yet.',
            ),
          if (s != null) ..._body(context, s),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, GuardState s) {
    final theme = Theme.of(context);
    final pace = s.pace;
    final progress = pace.target == 0
        ? 0.0
        : (pace.pages / pace.target).clamp(0.0, 1.0);
    final behind = pace.behind > 0;
    return [
      Text(
        s.locked ? 'PC locked: ${s.reason}' : s.reason,
        style: theme.textTheme.titleMedium?.copyWith(
          color: s.locked ? theme.colorScheme.error : null,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pace.month, style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${pace.pages} / ${pace.target} pages',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: AppSpacing.sm),
              Text(
                behind
                    ? "${pace.behind} pages behind today's line "
                          '(${pace.required})'
                    : 'On pace (line today: ${pace.required})',
                style: TextStyle(
                  color: behind ? theme.colorScheme.error : null,
                ),
              ),
              if (pace.carriedDebt > 0)
                Text(
                  'Includes ${pace.carriedDebt} pages carried from last month',
                ),
            ],
          ),
        ),
      ),
      if (s.todo.isNotEmpty) ...[
        const SectionHeader('Next'),
        for (final t in s.todo)
          ListTile(leading: const Icon(Icons.arrow_right), title: Text(t)),
      ],
      if (s.sessions.isNotEmpty) ...[
        const SectionHeader('Sessions'),
        for (final session in s.sessions.reversed)
          Builder(
            builder: (context) => ListTile(
              title: Text(
                'p. ${session.startPage}-${session.endPage} '
                '(${session.pages} p, ${session.minutes} min)',
              ),
              subtitle: Text(
                sessionStatusText[session.status] ?? session.status,
              ),
              trailing: api == null || session.detail.isEmpty
                  ? null
                  : const Icon(Icons.chevron_right),
              onTap: switch (api) {
                final api? when session.detail.isNotEmpty =>
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SessionScreen(api: api, session: session),
                    ),
                  ),
                _ => null,
              },
            ),
          ),
      ],
    ];
  }
}
