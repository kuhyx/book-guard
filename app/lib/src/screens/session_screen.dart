import 'dart:convert';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/screens/library_session_tile.dart'
    show photoRoleIcon;
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/session_status_icon.dart';
import 'package:book_guard_app/src/screens/session_times.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// One past session: its photos, what the PC read off them, the summary
/// written and what the grader said (book-guard `_session_files`).
class SessionScreen extends StatelessWidget {
  /// Creates the screen for [session].
  const new({required this.api, required this.session, super.key});

  /// Where the detail file and photos come from.
  final GuardApi api;

  /// The session as listed in the snapshot.
  final SessionInfo session;

  Future<Map<String, dynamic>?> _load() async {
    final bytes = await api.fetchBytes(session.detail);
    if (bytes == null) return null;
    final json = jsonDecode(utf8.decode(bytes));
    return json is Map<String, dynamic> ? json : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(pageSpan(session))),
    body: FutureBuilder<Map<String, dynamic>?>(
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final doc = snapshot.data;
        if (doc == null) {
          return const EmptyGlyph(
            Icons.hourglass_empty,
            semanticLabel: "The PC has not written this session's details yet",
          );
        }
        return _Detail(api: api, session: session, doc: doc);
      },
    ),
  );
}

class _Detail extends StatelessWidget {
  const new({required this.api, required this.session, required this.doc});

  final GuardApi api;
  final SessionInfo session;
  final Map<String, dynamic> doc;

  @override
  Widget build(BuildContext context) {
    final photos = [
      for (final p in doc['photos'] as List? ?? const [])
        if (p is Map<String, dynamic>) p,
    ];
    final summary = '${doc['summary'] ?? ''}';
    final feedback = '${doc['feedback'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('${doc['book'] ?? ''}'),
        Wrap(
          spacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconNumber(
              Icons.menu_book,
              '${session.pages}',
              semanticLabel: 'Pages',
            ),
            IconNumber(
              Icons.timer_outlined,
              '${session.minutes}',
              semanticLabel: 'Minutes',
            ),
            SessionStatusIcon(statusKey(session)),
          ],
        ),
        SessionTimes(api: api, session: session, onChanged: () async {}),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final p in photos)
              InkWell(
                onTap: () => openPhoto(context, api, '${p['file']}'),
                child: Column(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 128,
                      child: RemoteImage(
                        bytes: api.fetchBytes('${p['thumb']}'),
                        fit: BoxFit.cover,
                      ),
                    ),
                    _PhotoMark(p),
                  ],
                ),
              ),
          ],
        ),
        for (final p in photos)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Align(alignment: Alignment.centerLeft, child: _PhotoMark(p)),
            children: [SelectableText('${p['text'] ?? ''}')],
          ),
        const SizedBox(height: AppSpacing.md),
        if (summary.isEmpty)
          const EmptyGlyph(Icons.edit_note, semanticLabel: 'No summary yet')
        else
          SelectableText(summary),
        if (feedback.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.rate_review_outlined, semanticLabel: 'Grader'),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: SelectableText(feedback)),
            ],
          ),
        ],
      ],
    );
  }
}

/// A photo's role as a glyph and the page the PC read off it.
class _PhotoMark extends StatelessWidget {
  const new(this.photo);

  final Map<String, dynamic> photo;

  @override
  Widget build(BuildContext context) => IconNumber(
    photoRoleIcon('${photo['role']}'),
    '${photo['page'] ?? '?'}',
    semanticLabel: '${photo['role']}',
  );
}
