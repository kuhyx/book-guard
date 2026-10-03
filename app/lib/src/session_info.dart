/// One reading session as `state.json` lists it (split out of
/// `guard_state.dart`, which re-exports it).
library;

int? _int(Object? raw) => raw is int ? raw : int.tryParse('${raw ?? ''}');

/// One reading session.
class SessionInfo {
  /// Creates a session.
  const new({
    required this.id,
    required this.startPage,
    required this.endPage,
    required this.checkPage,
    required this.pages,
    required this.minutes,
    required this.status,
    required this.startedAt,
    this.detail = '',
    this.endedAt,
    this.photoStart,
    this.photoEnd,
    this.retry,
  });

  /// Parses one `sessions[]` entry.
  factory fromJson(Map<String, dynamic> json) => SessionInfo(
    id: '${json['id'] ?? ''}',
    startPage: _int(json['start_page']) ?? 0,
    endPage: _int(json['end_page']) ?? 0,
    checkPage: _int(json['check_page']),
    pages: _int(json['pages']) ?? 0,
    minutes: _int(json['minutes']) ?? 0,
    status: '${json['status'] ?? ''}',
    startedAt: DateTime.tryParse('${json['started_at']}'),
    detail: '${json['detail'] ?? ''}',
    endedAt: DateTime.tryParse('${json['ended_at']}'),
    photoStart: DateTime.tryParse('${json['photo_start']}'),
    photoEnd: DateTime.tryParse('${json['photo_end']}'),
    retry: RetryInfo.fromJson(json['retry']),
  );

  /// The session's detail file, relative to `Reading/`.
  final String detail;

  /// Ledger id (`session:<hash>-<hash>`).
  final String id;

  /// First page.
  final int startPage;

  /// Page where reading stopped.
  final int endPage;

  /// The page to photograph as proof, if one is needed.
  final int? checkPage;

  /// Pages read.
  final int pages;

  /// Minutes read.
  final int minutes;

  /// `needs-check-photo`, `needs-quiz`, `credited`, `failed-quiz`, `too-fast`.
  final String status;

  /// When reading began (the start photo, or a later time set by hand).
  final DateTime? startedAt;

  /// When reading ended (the end photo, or an earlier time set by hand).
  final DateTime? endedAt;

  /// The start photo's time: the earliest a start may be set to.
  final DateTime? photoStart;

  /// The end photo's time: the latest an end may be set to.
  final DateTime? photoEnd;

  /// A failed summary that may be rewritten once, if this is one.
  final RetryInfo? retry;

  /// Graded at least once: its times are the ones it was graded on.
  bool get graded =>
      status == 'credited' || status == 'failed-quiz' || retry != null;
}

/// The first, failed grading of a summary that may be rewritten once.
class RetryInfo {
  /// Creates the retry.
  const new({required this.feedback, required this.summary, this.gradedAt});

  /// Parses `sessions[].retry`; null when there is no rewrite to offer.
  static RetryInfo? fromJson(Object? json) => json is Map<String, dynamic>
      ? RetryInfo(
          feedback: '${json['feedback'] ?? ''}',
          summary: '${json['summary'] ?? ''}',
          gradedAt: DateTime.tryParse('${json['graded_at']}'),
        )
      : null;

  /// What the grader said.
  final String feedback;

  /// The summary that failed: the rewrite starts from it.
  final String summary;

  /// When it was graded: a "with the grader" marker older than this is stale.
  final DateTime? gradedAt;
}
