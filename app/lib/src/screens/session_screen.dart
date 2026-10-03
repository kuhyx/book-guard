import 'dart:convert';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/session_times.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
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
    appBar: AppBar(title: Text('p. ${session.startPage}-${session.endPage}')),
    body: FutureBuilder<Map<String, dynamic>?>(
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final doc = snapshot.data;
        if (doc == null) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text("The PC has not written this session's details yet."),
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
        Text(
          '${session.pages} pages in ${session.minutes} min - '
          '${statusText(session)}',
        ),
        SessionTimes(api: api, session: session, onChanged: () async {}),
        const SectionHeader('Photos'),
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
                    Text('${p['role']} - p. ${p['page'] ?? '?'}'),
                  ],
                ),
              ),
          ],
        ),
        const SectionHeader('What the PC read'),
        for (final p in photos)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('${p['role']} photo, p. ${p['page'] ?? '?'}'),
            children: [SelectableText('${p['text'] ?? ''}')],
          ),
        const SectionHeader('Your summary'),
        SelectableText(summary.isEmpty ? 'No summary written yet.' : summary),
        if (feedback.isNotEmpty) ...[
          const SectionHeader('Grader'),
          SelectableText(feedback),
        ],
      ],
    );
  }
}
