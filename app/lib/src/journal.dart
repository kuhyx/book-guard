import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_store.dart';

/// One photo this phone took, as it read it.
class JournalEntry {
  /// Creates an entry.
  const new({
    required this.name,
    required this.label,
    required this.sha,
    required this.takenAt,
    this.page,
    this.seen = false,
  });

  /// Parses one stored entry.
  factory fromJson(Map<String, dynamic> json) => JournalEntry(
    name: '${json['name']}',
    label: '${json['label']}',
    sha: '${json['sha']}',
    takenAt: DateTime.parse('${json['taken_at']}'),
    page: json['page'] as int?,
    seen: json['seen'] == true,
  );

  /// The name it is uploaded under.
  final String name;

  /// `start`, `stop` or `check<N>`.
  final String label;

  /// sha256 of the file, hex -- the PC's photo key.
  final String sha;

  /// When it was taken.
  final DateTime takenAt;

  /// The page number the phone read, if any.
  final int? page;

  /// Whether the PC has read it: kept once known, because `state.json`
  /// lists only its newest photos and the journal holds far more.
  final bool seen;

  /// This entry, marked as read by the PC.
  JournalEntry asSeen() => JournalEntry(
    name: name,
    label: label,
    sha: sha,
    takenAt: takenAt,
    page: page,
    seen: true,
  );

  /// The stored form.
  Map<String, Object?> toJson() => {
    'name': name,
    'label': label,
    'sha': sha,
    'taken_at': takenAt.toIso8601String(),
    'page': page,
    if (seen) 'seen': true,
  };
}

/// Every photo taken on this phone (newest [keep]), so it can name the
/// check page and the session while the PC is off.
class Journal {
  /// Creates a journal over [store].
  new(this.store);

  /// Where it lives.
  final LocalStore store;

  /// Entries kept.
  static const keep = 200;
  static const _file = 'journal.json';

  /// Every entry, oldest first.
  Future<List<JournalEntry>> load() async {
    final raw = await store.read(_file);
    if (raw == null) return [];
    return [
      for (final e in jsonDecode(utf8.decode(raw)) as List<dynamic>)
        JournalEntry.fromJson(e as Map<String, dynamic>),
    ];
  }

  final _serial = Serial();

  /// Appends [entry].
  Future<void> add(JournalEntry entry) => _serial.run(() async {
    final all = [...await load(), entry];
    await _save(all.length > keep ? all.sublist(all.length - keep) : all);
  });

  /// Marks every entry [state] shows the PC has read; written only when
  /// that changes anything.
  Future<void> markSeen(GuardState state) => _serial.run(() async {
    final all = await load();
    final known = knownToPc(state, all);
    if (all.every((e) => e.seen || !known.contains(e.name))) return;
    await _save([
      for (final e in all)
        if (known.contains(e.name)) e.asSeen() else e,
    ]);
  });

  Future<void> _save(List<JournalEntry> entries) => store.write(
    _file,
    Uint8List.fromList(
      utf8.encode(jsonEncode([for (final e in entries) e.toJson()])),
    ),
  );
}

final _filedSha = RegExp('^processed/([0-9a-f]{12})-');

/// The names in [journal] the PC has read -- for good, even once they have
/// left the newest photos `state.json` lists (`_state_json.py` `_photos`):
///
/// * marked [JournalEntry.seen], or listed now (by name, or by its bytes'
///   hash: a re-sent duplicate is filed under the first name);
/// * anything before the oldest entry listed: the outbox sends strictly in
///   order, so all of those went up first;
/// * anything taken before the oldest photo listed (the journal's time is
///   when the phone queued it, never before the photo was taken).
Set<String> knownToPc(GuardState? state, List<JournalEntry> journal) {
  final photos = state?.photos ?? const <PhotoInfo>[];
  final listed = {for (final p in photos) p.name};
  final hashes = {
    for (final p in photos) ?_filedSha.firstMatch(p.file)?.group(1),
  };
  final firstListed = journal.indexWhere((e) => listed.contains(e.name));
  DateTime? oldest;
  for (final p in photos) {
    final at = p.takenAt;
    if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
  }
  return {
    for (final (i, e) in journal.indexed)
      if (e.seen ||
          listed.contains(e.name) ||
          hashes.contains(e.sha.substring(0, 12)) ||
          i < firstListed ||
          (oldest != null && e.takenAt.isBefore(oldest)))
        e.name,
  };
}
