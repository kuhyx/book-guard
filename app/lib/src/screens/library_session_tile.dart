import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/library.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/screens/library_tab.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/session_status_icon.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The role of a session photo as a glyph (start, stop, check page).
IconData photoRoleIcon(String role) => switch (role) {
  'start' => Icons.play_arrow,
  'stop' || 'end' => Icons.stop,
  'check' => Icons.fact_check,
  _ => Icons.photo,
};

/// A grader's name as a glyph: Claude in the cloud, the local model on
/// this machine.
IconData graderIcon(String grader) =>
    grader.startsWith('local') ? Icons.computer : Icons.cloud;

/// One session of a library book: date, pages, minutes and status as
/// numbers and glyphs; expanded, its photos, summary and grader attempts.
class LibrarySessionTile extends StatelessWidget {
  /// Creates the tile for [session].
  const new({required this.api, required this.session, super.key});

  /// Where the photo thumbnails come from.
  final GuardApi api;

  /// The session.
  final LibrarySession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final last = s.attempts.isEmpty ? null : s.attempts.last;
    final earlier = s.attempts.length > 1
        ? s.attempts.sublist(0, s.attempts.length - 1)
        : const <
            ({bool passed, String summary, String feedback, String grader})
          >[];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Wrap(
        spacing: AppSpacing.md,
        children: [
          Text(dmy(s.endedAt)),
          Text(
            '${s.estimated ? '≈' : ''}'
            '${s.startPage ?? '?'}-${s.endPage ?? '?'}',
          ),
        ],
      ),
      subtitle: Wrap(
        spacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconNumber(
            Icons.menu_book,
            s.pages == null ? '?' : '${s.pages}',
            semanticLabel: 'Pages',
          ),
          IconNumber(
            Icons.timer_outlined,
            s.minutes == null ? '?' : '${s.minutes}',
            semanticLabel: 'Minutes',
          ),
          SessionStatusIcon(s.status, size: 18),
        ],
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.photos.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final p in s.photos)
                InkWell(
                  onTap: () => openPhoto(context, api, p.file),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 72,
                        height: 96,
                        child: RemoteImage(
                          bytes: api.fetchBytes(p.thumb),
                          fit: BoxFit.cover,
                        ),
                      ),
                      IconNumber(
                        photoRoleIcon(p.role),
                        p.page == null ? '?' : '${p.page}',
                        semanticLabel: p.role,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        if (last == null)
          const EmptyGlyph(Icons.edit_note, semanticLabel: 'No summary yet')
        else
          SelectableText(last.summary),
        if (last != null && last.feedback.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                graderIcon(last.grader),
                semanticLabel: last.grader.isEmpty ? 'Grader' : last.grader,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: SelectableText(last.feedback)),
            ],
          ),
        ],
        for (final (i, a) in earlier.indexed)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Row(
              children: [
                Icon(
                  a.passed ? Icons.check_circle : Icons.cancel,
                  color: a.passed
                      ? context.statusColors.success
                      : context.statusColors.danger,
                  semanticLabel: a.passed ? 'Passed' : 'Failed',
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('${i + 1}'),
              ],
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [SelectableText(a.summary), SelectableText(a.feedback)],
          ),
      ],
    );
  }
}
