import 'package:book_guard_app/src/index_job.dart';
import 'package:flutter_test/flutter_test.dart';

IndexJob job(
  String stage, {
  int done = 0,
  int total = 0,
  String error = '',
  DateTime? updatedAt,
}) => IndexJob(
  file: 'a.epub',
  stage: stage,
  done: done,
  total: total,
  error: error,
  updatedAt: updatedAt,
);

void main() {
  final now = DateTime.utc(2026, 10, 15, 12);

  test("parses the PC's job, numbers as ints or digit strings", () {
    final parsed = IndexJob.fromJson({
      'file': 'a.epub',
      'stage': 'embedding',
      'done': 3,
      'total': '10',
      'error': 'boom',
      'updated_at': '2026-10-15T11:00:00Z',
    });
    expect(parsed.file, 'a.epub');
    expect(parsed.stage, 'embedding');
    expect(parsed.done, 3);
    expect(parsed.total, 10);
    expect(parsed.error, 'boom');
    expect(parsed.updatedAt, DateTime.utc(2026, 10, 15, 11));
  });

  test('missing or bad fields fall back', () {
    final parsed = IndexJob.fromJson({'done': 'x', 'total': null});
    expect(parsed.file, '');
    expect(parsed.stage, '');
    expect(parsed.done, 0);
    expect(parsed.total, 0);
    expect(parsed.error, '');
    expect(parsed.updatedAt, isNull);
  });

  group('the 30-minute stale rule keys off updated_at', () {
    test('silent for over 30 minutes is stale and failed', () {
      final old = job(
        'extracting',
        updatedAt: now.subtract(const Duration(minutes: 31)),
      );
      expect(old.isStale(now), isTrue);
      expect(old.hasFailed(now), isTrue);
    });

    test('exactly 30 minutes, or a fresh job, is not', () {
      final edge = job(
        'embedding',
        updatedAt: now.subtract(const Duration(minutes: 30)),
      );
      expect(edge.isStale(now), isFalse);
      expect(job('uploaded', updatedAt: now).hasFailed(now), isFalse);
    });

    test('no timestamp can never be stale', () {
      expect(job('extracting').isStale(now), isFalse);
    });

    test('a finished job is never stale however old', () {
      final long = now.subtract(const Duration(days: 3));
      expect(job('done', updatedAt: long).isStale(now), isFalse);
      expect(job('done', updatedAt: long).hasFailed(now), isFalse);
      expect(job('failed', updatedAt: long).isStale(now), isFalse);
      expect(job('failed', updatedAt: long).hasFailed(now), isTrue);
    });
  });

  test('finished is done or failed', () {
    expect(job('done').finished, isTrue);
    expect(job('failed').finished, isTrue);
    expect(job('embedding').finished, isFalse);
  });

  test('fraction counts only while embedding', () {
    expect(job('done').fraction, 1);
    expect(job('embedding', done: 1, total: 4).fraction, 0.25);
    expect(job('embedding').fraction, isNull);
    expect(job('extracting', done: 1, total: 4).fraction, isNull);
  });

  test('one line per stage', () {
    expect(
      job('uploaded').describe(now),
      'a.epub: uploaded, waiting for the PC...',
    );
    expect(job('extracting').describe(now), 'a.epub: extracting the text...');
    expect(
      job('embedding', done: 3, total: 10).describe(now),
      'a.epub: indexing 3 / 10 passages...',
    );
    expect(
      job('done', total: 10).describe(now),
      'a.epub: indexed (10 passages).',
    );
    expect(job('failed').describe(now), 'a.epub: failed.');
    expect(
      job('failed', error: 'a.epub: no text').describe(now),
      'a.epub: no text',
    );
    expect(job('weird').describe(now), 'a.epub: weird');
  });

  test('a stale job says the PC stopped', () {
    final stale = job(
      'embedding',
      updatedAt: now.subtract(const Duration(hours: 2)),
    );
    expect(
      stale.describe(now),
      'a.epub: no progress for over 30 minutes - the PC stopped indexing it.',
    );
  });
}
