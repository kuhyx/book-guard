import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';

/// A summary survives leaving the tab: its text is kept as a draft, and a
/// summary sent to the grader is remembered until the PC has graded it.
/// (2026-10-03: switching tabs while grading lost both.)
extension SummaryStore on GuardApi {
  /// The draft typed for [sessionId], or "".
  Future<String> loadDraft(String sessionId) async {
    final raw = await store.read('drafts/$sessionId');
    return raw == null ? '' : utf8.decode(raw);
  }

  /// Keeps [text] as [sessionId]'s draft.
  Future<void> saveDraft(String sessionId, String text) =>
      store.write('drafts/$sessionId', Uint8List.fromList(utf8.encode(text)));

  /// Marks [sessionId]'s summary as sent to the grader.
  Future<void> markGrading(String sessionId) => store.write(
    'grading/$sessionId',
    Uint8List.fromList(utf8.encode(DateTime.now().toIso8601String())),
  );

  /// When [sessionId]'s summary went to the grader, if it is still out.
  Future<DateTime?> gradingSince(String sessionId) async {
    final raw = await store.read('grading/$sessionId');
    return raw == null ? null : DateTime.tryParse(utf8.decode(raw));
  }

  /// Sending [sessionId]'s summary failed: it can be sent again.
  Future<void> cancelGrading(String sessionId) =>
      store.delete('grading/$sessionId');

  /// [sessionId] was graded: forget its draft and its marker.
  Future<void> doneGrading(String sessionId) async {
    await store.delete('grading/$sessionId');
    await store.delete('drafts/$sessionId');
  }
}
