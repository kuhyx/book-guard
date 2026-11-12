import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/icon_num.dart';
import 'package:book_guard_app/src/screens/session_screen.dart';
import 'package:book_guard_app/src/screens/session_status_icon.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// One recent session: its status glyph, then the page range, the pages and
/// the minutes as numbers. Tapping opens its history when there is one.
class SessionRow extends StatelessWidget {
  /// Creates the row.
  const new({required this.session, this.api, super.key});

  /// The session.
  final SessionInfo session;

  /// For opening its history; null hides the chevron.
  final GuardApi? api;

  @override
  Widget build(BuildContext context) {
    final api = this.api;
    final open = api != null && session.detail.isNotEmpty;
    return ListTile(
      leading: SessionStatusIcon(statusKey(session), size: 28),
      title: Wrap(
        spacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconNum(
            Icons.import_contacts,
            '${session.estimated ? '≈' : ''}'
            '${session.startPage}-${session.endPage}',
          ),
          IconNum(pagesGlyph, '${session.pages}'),
          IconNum(minutesGlyph, '${session.minutes}'),
        ],
      ),
      trailing: open ? const Icon(Icons.chevron_right) : null,
      onTap: open
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SessionScreen(api: api, session: session),
              ),
            )
          : null,
    );
  }
}
