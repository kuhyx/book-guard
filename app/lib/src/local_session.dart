import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/journal.dart';
import 'package:crypto/crypto.dart';

export 'package:book_guard_app/src/journal.dart';

/// sha256 hex of a photo's bytes -- `book_guard/_photo.py` sha256_of.
String photoSha(Uint8List bytes) => sha256.convert(bytes).toString();

/// Seconds a page takes at the least; a stop on the start page sooner than
/// this is the start photo retaken (`book_guard/_constants.py`).
const minSecondsPerPage = 50;

/// The check page from [startPage] to [endPage], both included, exactly as
/// the PC names it (`book_guard/_sessions.py` check_page_for); null only
/// when the stop is before the start.
int? checkPageFor(int startPage, String startSha, int endPage, String endSha) {
  final low = startPage;
  final high = endPage;
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
      final seconds = e.takenAt.difference(start.takenAt).inSeconds;
      final retaken = page == startPage && seconds < minSecondsPerPage;
      if (startPage != null && retaken) {
        // The same page that soon is the start photo taken again. (The PC
        // also looks at the photo after a later same-page stop; the buttons
        // name the stop here.)
        (open, openPage) = (e, page);
        continue;
      }
      if (startPage != null && page >= startPage) {
        needCheck.add(
          SessionInfo(
            id: sessionId(start.sha, e.sha),
            startPage: startPage,
            endPage: page,
            checkPage: checkPageFor(startPage, start.sha, page, e.sha),
            pages: page - startPage + 1,
            minutes: seconds ~/ 60,
            startedAt: start.takenAt,
            status: 'needs-check-photo',
          ),
        );
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
