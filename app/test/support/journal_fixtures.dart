import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';

/// When the tests' journals begin.
final journalStart = DateTime.utc(2026, 10, 3, 12);

/// A journal entry [minutes] after [journalStart], hashed from its name.
JournalEntry journalEntry(String name, String label, int? page, int minutes) =>
    JournalEntry(
      name: name,
      label: label,
      sha: photoSha(Uint8List.fromList(utf8.encode(name))),
      takenAt: journalStart.add(Duration(minutes: minutes)),
      page: page,
    );

/// A snapshot listing [photos] by name, the way the PC's 40-photo window
/// does: newest first, each taken at [takenAt] (default: before anything in
/// the tests' journals, so time alone decides nothing). Its one session,
/// `session:pc`, waits for a photo of page 30.
GuardState windowState({
  int? openStart,
  List<String> photos = const [],
  DateTime? takenAt,
}) => GuardState.fromJson({
  'open_start': openStart == null ? null : {'page': openStart},
  'photos': [
    for (final p in photos.reversed)
      {
        'name': p,
        'file': 'processed/0123456789ab-$p',
        'kind': 'page',
        'status': 'ok',
        'taken_at': (takenAt ?? DateTime.utc(2026)).toIso8601String(),
      },
  ],
  'sessions': [
    {'id': 'session:pc', 'status': 'needs-check-photo', 'check_page': 30},
  ],
});
