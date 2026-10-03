import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _b(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  late MemoryStore store;

  setUp(() => store = MemoryStore());

  group('local session view', () {
    final t0 = DateTime.utc(2026, 10, 3, 12);
    JournalEntry e(String name, String label, int? page, int minutes) =>
        JournalEntry(
          name: name,
          label: label,
          sha: photoSha(_b(name)),
          takenAt: t0.add(Duration(minutes: minutes)),
          page: page,
        );

    GuardState state({int? openStart, List<String> photos = const []}) =>
        GuardState.fromJson({
          'open_start': openStart == null ? null : {'page': openStart},
          'photos': [
            for (final p in photos) {'name': p, 'kind': 'page', 'status': 'ok'},
          ],
          'sessions': [
            {
              'id': 'session:pc',
              'status': 'needs-check-photo',
              'check_page': 30,
            },
          ],
        });

    test('nothing pending: the PC is the whole truth', () {
      expect(localView(state(), []), isNull);
      expect(localView(null, []), isNull);
    });

    test('offline start, stop and check become a session to summarise', () {
      final start = e('start_a.jpg', 'start', 51, 0);
      final stop = e('stop_b.jpg', 'stop', 103, 50);
      final check = checkPageFor(51, start.sha, 103, stop.sha)!;
      expect(check, inInclusiveRange(52, 102));
      final view = localView(state(), [start, stop])!;
      expect(view.openStart, isNull);
      expect(view.waiting, 2);
      final local = view.needCheck.last;
      expect((local.checkPage, local.pages, local.minutes), (check, 52, 50));
      expect(local.id, sessionId(start.sha, stop.sha));
      final done = localView(state(), [
        start,
        stop,
        e('check_c', 'check$check', check, 52),
      ])!;
      expect(done.needCheck.map((s) => s.id), ['session:pc']);
      expect(done.needSummary.single.status, 'needs-quiz');
    });

    test('a start already read by the PC is matched for its hash', () {
      final start = e('start_a.jpg', 'start', 51, 0);
      final view = localView(state(openStart: 51, photos: ['start_a.jpg']), [
        start,
        e('stop_b.jpg', 'stop', 52, 5),
      ])!;
      // 51 -> 52 has no page between: straight to the summary.
      expect(view.needSummary.single.checkPage, isNull);
    });

    test('only a start pending: reading since its page', () {
      expect(localView(state(), [e('s', 'start', 60, 0)])!.openStart, 60);
    });

    test('a stop without a start, or going backwards, is no session', () {
      expect(
        localView(state(), [e('x', 'stop', 9, 0)])!.needCheck,
        hasLength(1),
      );
      final back = localView(state(), [
        e('s', 'start', 60, 0),
        e('t', 'stop', 50, 9),
      ])!;
      expect((back.openStart, back.needCheck.length), (null, 1));
      final unread = localView(state(), [
        e('s', 'start', null, 0),
        e('t', 'stop', 70, 9),
      ])!;
      expect(unread.needSummary, isEmpty);
    });

    test("a check photo answers the PC's own pending session", () {
      final view = localView(state(), [
        e('c', 'check30', 30, 0),
        e('d', 'check31', 31, 1),
      ])!;
      expect(view.needCheck, isEmpty);
      expect(view.needSummary.single.id, 'session:pc');
    });

    test('journal entries round-trip and the journal is capped', () async {
      final journal = Journal(store);
      for (var i = 0; i < Journal.keep + 1; i++) {
        await journal.add(e('n$i', 'start', i, i));
      }
      final all = await journal.load();
      expect(all, hasLength(Journal.keep));
      expect(all.first.name, 'n1');
      expect(all.last.takenAt, t0.add(const Duration(minutes: Journal.keep)));
    });
  });
}
