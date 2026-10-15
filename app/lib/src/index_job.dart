/// `state.json`'s `index_job`: where the PC's indexing of the last dropped
/// book file stands (book-guard `_indexjob`).
library;

int _int(Object? raw) => raw is int ? raw : int.tryParse('${raw ?? ''}') ?? 0;

/// One book file's indexing.
class IndexJob {
  /// Creates a job.
  const new({
    required this.file,
    required this.stage,
    this.done = 0,
    this.total = 0,
    this.error = '',
    this.updatedAt,
  });

  /// Parses `{file, stage, done, total, error, updated_at}`.
  factory fromJson(Map<String, dynamic> json) => IndexJob(
    file: '${json['file'] ?? ''}',
    stage: '${json['stage'] ?? ''}',
    done: _int(json['done']),
    total: _int(json['total']),
    error: '${json['error'] ?? ''}',
    updatedAt: DateTime.tryParse('${json['updated_at']}'),
  );

  /// A job silent this long is dead: the PC's oneshot pass can be killed
  /// mid-job (memory cap, timeout) without ever writing `failed`.
  static const staleAfter = Duration(minutes: 30);

  /// The file name as uploaded.
  final String file;

  /// `uploaded`, `extracting`, `embedding`, `done` or `failed`.
  final String stage;

  /// Chunks embedded so far.
  final int done;

  /// Chunks to embed (0 before the embedding stage).
  final int total;

  /// Why it failed (the PC's `books/failed/<file>.txt` line).
  final String error;

  /// When the PC last wrote it.
  final DateTime? updatedAt;

  /// Whether the job has ended, either way.
  bool get finished => stage == 'done' || stage == 'failed';

  /// Still running by its stage, but not updated for [staleAfter].
  bool isStale(DateTime now) =>
      !finished && updatedAt != null && now.difference(updatedAt!) > staleAfter;

  /// Failed outright, or stale.
  bool hasFailed(DateTime now) => stage == 'failed' || isStale(now);

  /// 0..1 through the embedding, or null while there is nothing to count.
  double? get fraction => switch (stage) {
    'done' => 1,
    'embedding' when total > 0 => done / total,
    _ => null,
  };

  /// One line for the Book tab.
  String describe(DateTime now) {
    if (isStale(now)) {
      return '$file: no progress for over 30 minutes - the PC stopped '
          'indexing it.';
    }
    return switch (stage) {
      'uploaded' => '$file: uploaded, waiting for the PC...',
      'extracting' => '$file: extracting the text...',
      'embedding' => '$file: indexing $done / $total passages...',
      'done' => '$file: indexed ($total passages).',
      'failed' => error.isEmpty ? '$file: failed.' : error,
      _ => '$file: $stage',
    };
  }
}
