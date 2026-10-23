import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/pace_panel.dart';
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

/// [session]'s status in words; a failed summary waiting for its rewrite
/// says so.
String statusText(SessionInfo session) => session.retry != null
    ? 'summary failed: rewrite it'
    : sessionStatusText[session.status] ?? session.status;

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

  /// The month: pages against the target, and the line today.
  List<Widget> _monthCard(ThemeData theme, Pace pace) {
    final progress = pace.target == 0
        ? 0.0
        : (pace.pages / pace.target).clamp(0.0, 1.0);
    final behind = pace.behind > 0;
    return [
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
        style: TextStyle(color: behind ? theme.colorScheme.error : null),
      ),
    ];
  }

  /// One number a day: today's pages against it first, the month after.
  List<Widget> _dayCard(ThemeData theme, Pace pace, int asks) {
    final read = pace.pagesToday;
    final met = pace.bonusToday || read >= asks;
    final short = asks - read;
    final more = '$short more ${short == 1 ? 'page' : 'pages'}';
    // A sick day asks nothing; its requirement still earns the hour.
    final sick = pace.todayQuota == 0 && asks > 0;
    return [
      Text('Today: $read / $asks pages', style: theme.textTheme.headlineSmall),
      const SizedBox(height: AppSpacing.sm),
      LinearProgressIndicator(
        value: asks == 0 ? 1.0 : (read / asks).clamp(0.0, 1.0),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(switch ((sick, met)) {
        (true, true) => 'Sick day: +1h earned',
        (true, false) =>
          'Sick day: nothing asked; $more still '
              '${short == 1 ? 'earns' : 'earn'} the +1h',
        (false, true) => 'On pace: PC open, +1h earned',
        (false, false) => '$more today: on pace, PC open, +1h',
      }),
      const SizedBox(height: AppSpacing.sm),
      Text(
        '${pace.month}: ${pace.pages} / ${pace.target} pages',
        style: theme.textTheme.bodyMedium,
      ),
    ];
  }

  List<Widget> _body(BuildContext context, GuardState s) {
    final theme = Theme.of(context);
    final pace = s.pace;
    final asks = pace.todayRequired;
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
              if (pace.daily && asks != null)
                ..._dayCard(theme, pace, asks)
              else
                ..._monthCard(theme, pace),
              if (pace.excused > 0)
                Text('Sick days excused: ${pace.excused} pages off the target'),
              if (pace.carriedDebt > 0)
                Text(
                  'Includes ${pace.carriedDebt} pages carried from last month',
                ),
            ],
          ),
        ),
      ),
      if (s.paceInputs case final inputs?) PacePanel(inputs: inputs),
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
                '${session.span} '
                '(${session.pages} p, ${session.minutes} min)',
              ),
              subtitle: Text(statusText(session)),
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
