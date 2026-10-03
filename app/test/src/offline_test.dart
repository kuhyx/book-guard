import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/error_log.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:book_guard_app/src/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_share.dart';

Uint8List _b(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  late FakeShare share;
  late MemoryStore store;
  late GuardApi api;

  setUp(() {
    share = FakeShare();
    store = MemoryStore();
    api = GuardApi(
      share.dav(),
      store: store,
      random: Random(1),
      pollEvery: Duration.zero,
      timeout: const Duration(milliseconds: 50),
    );
  });

  group('outbox', () {
    test('keeps order, stops at the first failure, resumes later', () async {
      final outbox = Outbox(store, share.dav());
      await outbox.put('inbox/a.jpg.json', _b('{}'));
      await outbox.put('inbox/a.jpg', _b('jpeg'));
      share.down = true;
      expect(await outbox.flush(), 2);
      expect(outbox.lastError?.status, 0);
      expect(await outbox.pending(), 2);
      share.down = false;
      expect(await outbox.flush(), 0);
      expect(outbox.lastError, isNull);
      expect(share.files.keys, [
        'Reading/inbox/a.jpg.json',
        'Reading/inbox/a.jpg',
      ]);
      expect(await store.list('outbox/'), isEmpty);
    });

    test('an item whose body is gone is dropped', () async {
      final outbox = Outbox(store, share.dav());
      await outbox.put('x', _b('1'));
      final body = (await store.list('outbox/'))
          .firstWhere((n) => n.endsWith('.body'));
      await store.delete(body);
      expect(await outbox.flush(), 0);
      expect(share.files, isEmpty);
    });

    test('concurrent flushes share one run', () async {
      final outbox = Outbox(store, share.dav());
      await outbox.put('x', _b('1'));
      final both = await Future.wait([outbox.flush(), outbox.flush()]);
      expect(both, [0, 0]);
      expect(share.requests, hasLength(1));
    });
  });

  group('error log', () {
    test('keeps the newest entries and queues each for the PC', () async {
      final outbox = Outbox(store, share.dav());
      final log = ErrorLog(
        store,
        outbox,
        host: 'phone',
        clock: () => DateTime.utc(2026, 10, 3, 12, 27),
        random: Random(2),
      );
      for (var i = 0; i < ErrorLog.keep + 3; i++) {
        await log.log('upload', 'failed $i', {'n': i});
      }
      final kept = utf8.decode((await store.read('errors.jsonl'))!);
      expect(const LineSplitter().convert(kept), hasLength(ErrorLog.keep));
      expect(kept, isNot(contains('"failed 2"')));
      share.down = true;
      await outbox.flush();
      final report = await log.diagnostics(last: 2);
      expect(report, contains('waiting to send: ${ErrorLog.keep + 3}'));
      expect(report, contains('last send failed'));
      expect(report, contains('"failed ${ErrorLog.keep + 2}"'));
      expect(report, isNot(contains('"failed 0"')));
      share.down = false;
      await outbox.flush();
      final sent = share.files.keys.where(
        (k) => k.startsWith('Reading/logs/phone/'),
      );
      expect(sent, hasLength(ErrorLog.keep + 3));
      final entry = jsonDecode(share.text(sent.first)!) as Map<String, dynamic>;
      expect(entry, containsPair('host', 'phone'));
      expect(entry, containsPair('stage', 'upload'));
    });

    test('an empty log still reports its queue', () async {
      final log = ErrorLog(store, Outbox(store, share.dav()), host: 'desktop');
      expect(await log.diagnostics(), contains('waiting to send: 0'));
    });
  });

  group('GuardApi offline', () {
    test('the last snapshot is kept for when the PC is unreachable', () async {
      expect(await api.cachedState(), isNull);
      share.putText('Reading/state.json', jsonEncode({'reason': 'on pace'}));
      await api.fetchState();
      share.down = true;
      await expectLater(api.fetchState(), throwsA(isA<DavException>()));
      expect((await api.cachedState())?.reason, 'on pace');
    });

    test(
      'a queued summary waits on the phone, its answer comes later',
      () async {
        share.down = true;
        final queued = await api.sendQueued('summary', {
          's': 1,
        }, 'Summary p. 51-103');
        expect(queued.ok, isTrue);
        expect(queued.message, contains('Saved on the phone'));
        share.down = false;
        expect(await api.collectAnswers(), isEmpty); // sent, not answered yet
        await api.flush();
        final request = share.files.keys.singleWhere(
          (k) => k.startsWith('Reading/requests/'),
        );
        final id = request.split('/').last.replaceAll('.json', '');
        share.putText(
          'Reading/responses/$id.json',
          jsonEncode({'ok': true, 'message': 'Credited', 'passed': true}),
        );
        final answer = (await api.collectAnswers()).single;
        expect(answer.what, 'Summary p. 51-103');
        expect(answer.response.passed, isTrue);
        expect(await api.collectAnswers(), isEmpty);
      },
    );

    test('online, a queued request is answered at once', () async {
      share.answer = (r) => {'ok': true, 'message': 'graded ${r['type']}'};
      final response = await api.sendQueued('summary', {}, 'what');
      expect(response.message, 'graded summary');
      expect(await store.list('pending/'), isEmpty);
    });

    test('online but unanswered: not yet, and kept for later', () async {
      final response = await api.sendQueued('summary', {}, 'what');
      expect(response.message, contains('has not answered yet'));
      expect(await store.list('pending/'), hasLength(1));
    });

    test('photos go up with their sidecar and are journalled', () async {
      final name = await api.queuePhoto(
        'start',
        'IMG 1.jpg',
        _b('jpeg'),
        page: 51,
        box: (left: 1, top: 2, right: 3, bottom: 4),
        takenAt: DateTime.utc(2026, 10, 3),
      );
      await api.queuePhoto('stop', 'IMG2.jpg', _b('jpeg2'));
      expect(name, 'start_IMG_1.jpg');
      await api.flush();
      expect(jsonDecode(share.text('Reading/inbox/start_IMG_1.jpg.json')!), {
        'page': 51,
        'box': [1, 2, 3, 4],
      });
      expect(
        share.files.containsKey('Reading/inbox/stop_IMG2.jpg.json'),
        isFalse,
      );
      final (first, second) = switch (await api.journal.load()) {
        [final a, final b] => (a, b),
        _ => throw StateError('two entries expected'),
      };
      expect(
        (first.label, first.page, first.sha),
        ('start', 51, photoSha(_b('jpeg'))),
      );
      expect(second.page, isNull);
      expect(await api.localPhoto(name), _b('jpeg'));
    });

    test('only the newest photos are kept on the device', () async {
      for (var i = 0; i < keptPhotos + 2; i++) {
        await api.queuePhoto('start', 'p$i.jpg', _b('$i'));
      }
      expect(await store.list('photos/'), hasLength(keptPhotos));
      expect(await api.localPhoto('start_p0.jpg'), isNull);
    });

    test('a bug report carries the photo and what was made of it', () async {
      expect(await api.reported('start_a.jpg'), isFalse);
      await api.reportPhoto(
        name: 'start_a.jpg',
        bytes: _b('jpeg'),
        detail: {'actual_page': 7},
      );
      await api.flush();
      expect(await api.reported('start_a.jpg'), isTrue);
      final note = share.files.keys.singleWhere((k) => k.endsWith('.json'));
      final body = jsonDecode(share.text(note)!) as Map<String, dynamic>;
      expect(body['photo'], 'start_a.jpg');
      expect(body['actual_page'], 7);
      expect(share.files[note.replaceAll('.json', '.jpg')], _b('jpeg'));
    });

    test('a contents photo offline says it was not sent', () async {
      share.down = true;
      expect(await api.uploadPhoto('toc-a.jpg', _b('x')), ('toc-a.jpg', false));
    });
  });
}
