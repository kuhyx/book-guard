import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/journal_fixtures.dart';

void main() {
  group('local session view', () {
    final t0 = journalStart;
    const e = journalEntry;

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

    test('a full journal: entries outside the PC window are not replayed', () {
      // 2026-10-23: the journal keeps 200 photos, state.json only the 40
      // newest -- every older one used to count as "not read yet" and
      // rebuild sessions the PC closed weeks ago.
      final journal = [
        e('old_start', 'start', 104, 0),
        e('old_stop', 'stop', 151, 50),
        e('old_check', 'check119', 119, 52),
        e('old_check30', 'check30', 30, 53),
        for (var i = 4; i < Journal.keep - 2; i++)
          e('n$i', i.isEven ? 'start' : 'stop', 200 + i, 60 * i),
        e('new_start', 'start', 600, 60 * 300),
        e('new_stop', 'stop', 620, 60 * 300 + 30),
      ];
      final listed = journal.sublist(Journal.keep - 42, Journal.keep - 2);
      final view = localView(
        windowState(photos: [for (final p in listed) p.name]),
        journal,
      )!;
      expect(view.waiting, 2);
      expect(view.needSummary, isEmpty);
      expect(view.needCheck.map((s) => (s.startPage, s.endPage)), [
        (0, 0), // the PC's own session:pc, unanswered by the old check30
        (600, 620),
      ]);
      expect(view.openStart, isNull);
      expect(
        failedPhotos(windowState(photos: [listed.last.name]), [
          e('old_unread', 'start', null, 0),
          ...listed,
          e('new_unread', 'start', null, 60 * 400),
        ]).map((f) => f.entry.name),
        ['new_unread'],
      );
    });

    test('photos older than the whole PC window are known by time', () {
      // Nothing the phone took is listed (desktop uploads filled the
      // window): what was taken before its oldest photo is long read.
      final old = [e('a', 'start', 104, 0), e('b', 'stop', 151, 50)];
      final fresh = e('c', 'start', 300, 600);
      final view = localView(
        windowState(
          photos: ['desktop1', 'desktop2'],
          takenAt: t0.add(const Duration(minutes: 100)),
        ),
        [...old, fresh],
      )!;
      expect((view.waiting, view.openStart), (1, 300));
      expect(view.needSummary, isEmpty);
    });

    test("today's sequence: the PC's open start stays open", () {
      // The PC read start p252 and lists it; the old Oct 4 start/stop/check
      // dropped out of its window. The app must say "Stop reading".
      final journal = [
        e('start_104', 'start', 104, 0),
        e('stop_151', 'stop', 151, 50),
        e('check119', 'check119', 119, 52),
        for (var i = 0; i < 39; i++) e('w$i', 'check$i', i, 100 + i),
        e('start_252', 'start', 252, 1000),
      ];
      final listed = [for (final p in journal.skip(3)) p.name];
      final pc = windowState(openStart: 252, photos: listed);
      expect(localView(pc, journal), isNull);
      // A genuinely new check photo is still pending -- and still leaves
      // the session the PC holds open.
      final view = localView(pc, [...journal, e('c30', 'check30', 30, 1010)])!;
      expect((view.openStart, view.waiting), (252, 1));
      expect(view.needSummary.single.id, 'session:pc');
    });

    test('a new start not uploaded yet is pending and shown', () {
      final journal = [
        for (var i = 0; i < 40; i++) e('w$i', 'check$i', i, i),
        e('start_new', 'start', 260, 100),
      ];
      final view = localView(
        windowState(photos: [for (final p in journal.take(40)) p.name]),
        journal,
      )!;
      expect((view.openStart, view.waiting), (260, 1));
    });
  });
}
