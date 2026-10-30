import 'package:book_guard_app/src/ebook_store.dart';

/// The longest wall-clock span a session may have (`MAX_SESSION` on the PC).
const maxSession = Duration(hours: 6);

/// Under this per page, the PC counts the session as flipped through.
const minSecondsPerPage = 50;

/// What closing the reader does with the running session. Closing never
/// asks: what the PC would refuse is dropped, and only a too-fast session
/// says so, because the reader may not expect it.
enum ReaderExit {
  /// Nothing was running.
  none,

  /// Not a page on: dropped silently.
  underAPage,

  /// Started more than [maxSession] ago: dropped silently.
  tooLong,

  /// Under [minSecondsPerPage] a page: dropped, with a toast.
  tooFast,

  /// Stopped and queued for the PC.
  stop,
}

/// Judges closing at [offset] and [now] with [start] running.
ReaderExit judgeExit(
  ReadingStart? start,
  int offset,
  EbookMap map,
  DateTime now,
) {
  if (start == null) return ReaderExit.none;
  final pages = map.pageAt(offset) - map.pageAt(start.offset);
  final elapsed = now.difference(start.startedAt);
  if (pages <= 0) return ReaderExit.underAPage;
  if (elapsed > maxSession) return ReaderExit.tooLong;
  if (elapsed.inSeconds < pages * minSecondsPerPage) return ReaderExit.tooFast;
  return ReaderExit.stop;
}

/// Whether a start kept on the device is too old to go on with at [now]
/// (the app was killed mid-session long ago): it is dropped on opening.
bool isStale(ReadingStart start, DateTime now) =>
    now.difference(start.startedAt) > maxSession;
