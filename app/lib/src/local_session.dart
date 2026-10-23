import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/journal.dart';
import 'package:crypto/crypto.dart';

export 'package:book_guard_app/src/journal.dart';

/// sha256 hex of a photo's bytes -- `book_guard/_photo.py` sha256_of.
String photoSha(Uint8List bytes) => sha256.convert(bytes).toString();

/// The check page between [startPage] and [endPage], exactly as the PC
/// names it (`book_guard/_sessions.py` check_page_for); null when there is
/// no page strictly between.
int? checkPageFor(int startPage, String startSha, int endPage, String endSha) {
  final low = startPage + 1;
  final high = endPage - 1;
  if (high < low) return null;
  final digest = sha256.convert(utf8.encode(startSha + endSha)).bytes;
  var seed = BigInt.zero;
  for (final byte in digest.take(8)) {
    seed = (seed << 8) | BigInt.from(byte);
  }
  return low + (seed % BigInt.from(high - low + 1)).toInt();
}

/// The PC's id for the session from [startSha] to [endSha].
String sessionId(String startSha, String endSha) =>
    'session:${startSha.substring(0, 16)}-${endSha.substring(0, 16)}';

/// What the phone knows that the PC has not read yet.
class LocalView {
  /// Creates a view.
  const new({
    required this.openStart,
    required this.needCheck,
    required this.needSummary,
    required this.waiting,
  });

  /// The page reading started at, by the phone's photos.
  final int? openStart;

  /// Sessions whose check page is still to be photographed.
  final List<SessionInfo> needCheck;

  /// Sessions waiting for a summary.
  final List<SessionInfo> needSummary;

  /// Photos taken here that the PC has not read yet.
  final int waiting;
}

/// The phone's view of photos [journal] holds that [state] does not yet
/// show; null when the PC has read every one of them.
LocalView? localView(GuardState? state, List<JournalEntry> journal) {
  final known = knownToPc(state, journal);
  final pending = [
    for (final e in journal)
      if (!known.contains(e.name)) e,
  ];
  if (pending.isEmpty) return null;
  JournalEntry? open;
  final pcStart = state?.openStart;
  if (pcStart != null) {
    for (final e in journal.reversed) {
      if (known.contains(e.name) && e.label == 'start' && e.page == pcStart) {
        open = e;
        break;
      }
    }
  }
  var openPage = open?.page ?? pcStart;
  // Start from what the PC already asks for; pending photos then answer
  // those or add sessions of their own.
  final needCheck = [...?state?.needCheck];
  final needSummary = [...?state?.needSummary];
  for (final e in pending) {
    final page = e.page;
    if (e.label == 'start') {
      (open, openPage) = (e, page);
    } else if (e.label == 'stop' && open != null && page != null) {
      final start = open;
      final startPage = start.page;
      if (startPage != null && page > startPage) {
        final check = checkPageFor(startPage, start.sha, page, e.sha);
        final session = SessionInfo(
          id: sessionId(start.sha, e.sha),
          startPage: startPage,
          endPage: page,
          checkPage: check,
          pages: page - startPage,
          minutes: e.takenAt.difference(start.takenAt).inMinutes,
          startedAt: start.takenAt,
          status: check == null ? 'needs-quiz' : 'needs-check-photo',
        );
        (check == null ? needSummary : needCheck).add(session);
      }
      (open, openPage) = (null, null);
    } else if (e.label.startsWith('check')) {
      final wanted = int.tryParse(e.label.substring(5));
      final hit = needCheck.where((s) => s.checkPage == wanted).firstOrNull;
      if (hit != null) {
        needCheck.remove(hit);
        needSummary.add(
          SessionInfo(
            id: hit.id,
            startPage: hit.startPage,
            endPage: hit.endPage,
            checkPage: hit.checkPage,
            pages: hit.pages,
            minutes: hit.minutes,
            startedAt: hit.startedAt,
            status: 'needs-quiz',
          ),
        );
      }
    }
  }
  return LocalView(
    openStart: openPage,
    needCheck: needCheck,
    needSummary: needSummary,
    waiting: pending.length,
  );
}
