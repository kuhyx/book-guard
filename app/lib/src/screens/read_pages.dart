import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/ebook_entry.dart';
import 'package:book_guard_app/src/screens/photo_status.dart';
import 'package:book_guard_app/src/screens/read_support.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The Read tab's session: start / stop / check, the e-book, the
/// summary. It fits the screen; it scrolls only while the keyboard is up
/// for the summary.
class ReadSessionPage extends StatelessWidget {
  /// Creates the page.
  const new({
    required this.api,
    required this.state,
    required this.waiting,
    required this.reading,
    required this.quiz,
    required this.status,
    required this.onChanged,
    required this.buttons,
    super.key,
  });

  /// The PC.
  final GuardApi api;

  /// The latest snapshot (possibly the cached one).
  final GuardState? state;

  /// Items still waiting on the phone for the PC.
  final int waiting;

  /// The open paper session's start page, if one is open.
  final int? reading;

  /// Sessions waiting for a summary; the first gets the panel.
  final List<SessionInfo> quiz;

  /// The last photo's fate, if any.
  final PhotoStatus? status;

  /// Refetch the snapshot after an action.
  final Future<void> Function() onChanged;

  /// The photo buttons.
  final Widget buttons;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SessionPrompt(waiting: waiting),
        const SizedBox(height: AppSpacing.md),
        buttons,
        EbookEntry(
          api: api,
          state: state,
          paperStart: reading,
          onChanged: onChanged,
        ),
        if (status case final status?) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            // A new status is a new chip: it buzzes once as it appears.
            child: PhotoStatusChip(status, key: ObjectKey(status)),
          ),
        ],
        if (quiz.isNotEmpty)
          SummaryPanel(
            key: ValueKey(quiz.first.id),
            api: api,
            session: quiz.first,
            state: state,
            pace: state?.pace,
            onChanged: onChanged,
          ),
      ],
    ),
  );
}
