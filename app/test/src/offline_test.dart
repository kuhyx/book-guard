import 'dart:convert';
import 'dart:io';
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

    test('a snapshot listing a photo marks it read for good', () async {
      await api.queuePhoto('start', 'a.jpg', _b('a'));
      await api.queuePhoto('stop', 'b.jpg', _b('b'));
      share.putText(
        'Reading/state.json',
        jsonEncode({
          'photos': [
            {'name': 'start_a.jpg', 'file': 'processed/x-start_a.jpg'},
          ],
        }),
      );
      await api.fetchState();
      final [a, b] = await api.journal.load();
      expect((a.seen, b.seen), (true, false));
    });

    test('lifecycle events wait in their own queue and go up', () async {
      await api.errors.event('photo', 'camera', {'attempt': 'a1'});
      expect(await api.outbox.pending(), 0); // not "waiting on the phone"
      expect(await api.eventbox.pending(), 1);
      expect(await api.flush(), 0);
      final [sent] = share.files.keys.toList();
      expect(sent, startsWith('Reading/logs/phone/'));
      expect(jsonDecode(share.text(sent)!), {
        'at': isA<String>(),
        'host': 'phone',
        'level': 'event',
        'stage': 'photo',
        'event': 'camera',
        'attempt': 'a1',
      });
    });

    test('an event that cannot be stored is dropped, never thrown', () async {
      final log = ErrorLog(
        _BrokenStore(),
        Outbox(_BrokenStore(), share.dav()),
        host: 'phone',
      );
      await log.event('photo', 'camera');
    });

    test('a photo upload reports itself: failed once, then sent', () async {
      await api.queuePhoto('start', 'a.jpg', _b('a'), page: 7);
      share.down = true;
      await api.flush();
      await api.flush(); // still down: no second "failed"
      share.down = false;
      await api.flush();
      await api.flush(); // the "uploaded" event itself goes up
      final logged = [
        for (final k in share.files.keys)
          if (k.startsWith('Reading/logs/phone/'))
            jsonDecode(share.text(k)!) as Map<String, dynamic>,
      ];
      expect(
        [for (final e in logged) (e['event'], e['photo'])],
        unorderedEquals([
          ('upload-failed', 'start_a.jpg'),
          ('uploaded', 'start_a.jpg'),
        ]),
      );
      expect(
        logged.firstWhere((e) => e['event'] == 'upload-failed')['error'],
        contains('unreachable'),
      );
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

/// A store whose every call fails, like a full or vanished disk.
class _BrokenStore implements LocalStore {
  @override
  Future<Uint8List?> read(String name) => throw const FileSystemException('x');

  @override
  Future<void> write(String name, Uint8List bytes) =>
      throw const FileSystemException('x');

  @override
  Future<void> delete(String name) => throw const FileSystemException('x');

  @override
  Future<List<String>> list(String prefix) =>
      throw const FileSystemException('x');
}
